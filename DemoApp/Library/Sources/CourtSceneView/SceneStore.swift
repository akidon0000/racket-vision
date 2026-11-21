import BallTracking
import CourtFit
import CourtScene
import PlayerPose
import RealityKit
import SwiftUI

/// 3D の場面に置く物（コート、選手、球、映像のカメラ）を持ち、結果が変わるたびに動かす。
/// 物は使い回す（毎回作り直すと重い）。使わない物は隠す。
@MainActor
final class SceneStore {
    let root = Entity()
    let camera = PerspectiveCamera()

    /// 映像のカメラの印（本体、写している範囲の 4 本の線、地面からの柱）。
    private let videoCamera = Entity()
    private let cameraBody = ModelEntity()
    private var cameraRays = [ModelEntity]()
    private let cameraPole = ModelEntity()
    private let cameraFoot = ModelEntity()
    private var joints = [Int: [PoseJoint: ModelEntity]]()
    private var bones = [Int: [ModelEntity]]()
    private var balls = [ModelEntity]()
    private var livePoints = [ModelEntity]()
    private var liveBall = [ModelEntity]()
    private let jointMesh = MeshResource.generateSphere(radius: 0.06)
    private let boneMesh = MeshResource.generateCylinder(height: 1, radius: 0.025)
    /// 球は、本物（半径 3.7 cm）より大きく描く（遠くから見ても分かるように）。
    private let ballMesh = MeshResource.generateSphere(radius: 0.1)
    /// 軌跡の点。細かく並べるので小さくする。
    private let trailMesh = MeshResource.generateSphere(radius: 0.04)

    init() {
        root.addChild(makeCourt())
        makeVideoCamera()
    }

    /// 今の視点の位置。
    private var eye = SIMD3<Double>(0, 0, 0)

    /// 視点を動かす。`aspect` は、描く範囲の横 ÷ 縦。
    func apply(_ orbit: SceneOrbit, aspect: Double) {
        camera.camera.fieldOfViewInDegrees = Float(orbit.verticalFieldOfView(aspect: aspect) * 180 / .pi)
        camera.look(at: .zero, from: SIMD3<Float>(orbit.position), relativeTo: nil)
        eye = orbit.position
    }

    /// 結果を、場面に反映する。`trajectory` は計算後の球の軌跡（細かく並べた点）、`live` はリアルタイムの球の点（最後が今の球）。
    func update(
        courtCamera: CourtCamera?, players: [ScenePlayer], trajectory: [SIMD3<Double>], live: [SIMD3<Double>], rallyColor: SIMD3<Double>
    ) {
        updateVideoCamera(courtCamera)
        updatePlayers(players)
        updateTrajectory(trajectory, color: rallyColor)
        updateLive(live)
    }

    // MARK: - コート

    private func makeCourt() -> Entity {
        let court = Entity()
        let model = CourtModel.pickleball
        let surface = ModelEntity(
            mesh: .generateBox(width: Float(model.width + 1.2), height: 0.01, depth: Float(model.length + 2)),
            materials: [UnlitMaterial(color: UIColorCompat.white(0.95))]
        )
        surface.position.y = -0.006
        court.addChild(surface)
        let lineMaterial = UnlitMaterial(color: UIColorCompat.white(0.55))
        for segment in CourtPlane.pickleballLines {
            let start = CourtSpace.point(onCourt: segment.start)
            let end = CourtSpace.point(onCourt: segment.end)
            let length = Float(simd_distance(start, end))
            let isAcross = abs(start.x - end.x) > abs(start.z - end.z)
            let line = ModelEntity(
                mesh: .generateBox(width: isAcross ? length : 0.05, height: 0.005, depth: isAcross ? 0.05 : length),
                materials: [lineMaterial]
            )
            line.position = SIMD3<Float>((start + end) / 2)
            court.addChild(line)
        }
        // ネット（高さ 0.86 m、両脇に 0.3 m はみ出す）。
        var netMaterial = UnlitMaterial(color: UIColorCompat.white(0.3))
        netMaterial.blending = .transparent(opacity: 0.25)
        let net = ModelEntity(mesh: .generateBox(width: Float(model.width + 0.6), height: 0.86, depth: 0.02), materials: [netMaterial])
        net.position.y = 0.43
        court.addChild(net)
        return court
    }

    // MARK: - 映像のカメラ

    /// 映像のカメラの印を作る。本体は黒い箱（レンズの側に青い円）、写している範囲は映像の四隅を通る 4 本の線、
    /// 高さは地面からの柱で見せる。
    private func makeVideoCamera() {
        cameraBody.model = ModelComponent(
            mesh: .generateBox(width: 0.32, height: 0.2, depth: 0.14, cornerRadius: 0.02),
            materials: [UnlitMaterial(color: UIColorCompat.white(0.1))]
        )
        let lens = ModelEntity(
            mesh: .generateCylinder(height: 0.06, radius: 0.07),
            materials: [UnlitMaterial(color: UIColorCompat.rgb(SIMD3(0.15, 0.45, 0.95), alpha: 1))]
        )
        // 円柱は y の向きに伸びている。本体の前（-z）に、レンズとして寝かせて付ける。
        lens.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        lens.position = SIMD3(0, 0, -0.09)
        cameraBody.addChild(lens)
        videoCamera.addChild(cameraBody)
        var rayMaterial = UnlitMaterial(color: UIColorCompat.rgb(SIMD3(0.15, 0.45, 0.95), alpha: 1))
        rayMaterial.blending = .transparent(opacity: 0.6)
        let rayMesh = MeshResource.generateCylinder(height: 1, radius: 0.012)
        cameraRays = (0..<4).map { _ in
            let ray = ModelEntity(mesh: rayMesh, materials: [rayMaterial])
            videoCamera.addChild(ray)
            return ray
        }
        cameraPole.model = ModelComponent(
            mesh: .generateCylinder(height: 1, radius: 0.015), materials: [UnlitMaterial(color: UIColorCompat.white(0.35))]
        )
        videoCamera.addChild(cameraPole)
        cameraFoot.model = ModelComponent(
            mesh: .generateCylinder(height: 0.01, radius: 0.25), materials: [UnlitMaterial(color: UIColorCompat.white(0.35))]
        )
        videoCamera.addChild(cameraFoot)
        videoCamera.isEnabled = false
        root.addChild(videoCamera)
    }

    private func updateVideoCamera(_ courtCamera: CourtCamera?) {
        guard let courtCamera else {
            videoCamera.isEnabled = false
            return
        }
        let position = courtCamera.position
        // 視点が映像のカメラの位置そのもの（「カメラの視点」）のときは、目の前を覆ってしまうので出さない。
        videoCamera.isEnabled = simd_distance(eye, position) > 0.5
        // 本体の向き: 箱の x を映像の右、y を映像の上、-z を見ている向きにそろえる。
        let right = simd_normalize(simd_cross(courtCamera.forward, courtCamera.up))
        let axes = simd_float3x3(columns: (SIMD3<Float>(right), SIMD3<Float>(courtCamera.up), SIMD3<Float>(-courtCamera.forward)))
        cameraBody.position = SIMD3<Float>(position)
        cameraBody.orientation = simd_quatf(axes)
        // 写している範囲: 映像の四隅を通る線を、地面に当たる所まで（遠ければ 8 m で止めて）引く。
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        for (ray, corner) in zip(cameraRays, corners) {
            let direction = courtCamera.direction(through: corner)
            let toGround = courtCamera.groundPoint(for: corner).map { simd_distance($0, position) } ?? .infinity
            place(ray, from: position, to: position + direction * min(toGround, 8))
        }
        let foot = SIMD3(position.x, 0, position.z)
        place(cameraPole, from: foot, to: position)
        cameraFoot.position = SIMD3<Float>(foot)
    }

    // MARK: - 選手

    private func updatePlayers(_ players: [ScenePlayer]) {
        let shown = Set(players.map(\.id))
        for (id, entities) in joints where !shown.contains(id) {
            entities.values.forEach { $0.isEnabled = false }
            bones[id]?.forEach { $0.isEnabled = false }
        }
        for player in players {
            let rgb = PlayerPalette.color(forPlayer: player.id)
            var material = UnlitMaterial(color: UIColorCompat.rgb(rgb, alpha: 1))
            if !player.isDetected {
                // 少し前の骨格をそのまま出しているときは、薄く描く。
                material.blending = .transparent(opacity: 0.45)
            }
            var playerJoints = joints[player.id] ?? [:]
            for joint in PoseJoint.allCases {
                let entity = playerJoints[joint] ?? makeEntity(mesh: jointMesh)
                playerJoints[joint] = entity
                guard let point = player.joints[joint] else {
                    entity.isEnabled = false
                    continue
                }
                entity.isEnabled = true
                entity.position = SIMD3<Float>(point)
                entity.model?.materials = [material]
            }
            joints[player.id] = playerJoints
            var playerBones = bones[player.id] ?? []
            while playerBones.count < PoseBone.body.count {
                playerBones.append(makeEntity(mesh: boneMesh))
            }
            for (index, bone) in PoseBone.body.enumerated() {
                let entity = playerBones[index]
                guard let start = player.joints[bone.start], let end = player.joints[bone.end] else {
                    entity.isEnabled = false
                    continue
                }
                place(entity, from: start, to: end)
                entity.model?.materials = [material]
            }
            bones[player.id] = playerBones
        }
    }

    // MARK: - 球

    /// 計算後の軌跡。細かく並べた小さな点で、線のように見せる。
    private func updateTrajectory(_ positions: [SIMD3<Double>], color: SIMD3<Double>) {
        // ラリーの色には白もあるので、白い背景で見えるよう、黒へ 4 割寄せる。
        let material = UnlitMaterial(color: UIColorCompat.rgb(color * 0.6, alpha: 1))
        show(positions, in: &balls, mesh: trailMesh, material: material)
    }

    /// リアルタイムの球。今ある点を灰色の小さな点で、今の球を大きな橙の球で描く。
    private func updateLive(_ positions: [SIMD3<Double>]) {
        show(Array(positions.dropLast()), in: &livePoints, mesh: trailMesh, material: UnlitMaterial(color: UIColorCompat.white(0.55)))
        show(positions.last.map { [$0] } ?? [], in: &liveBall, mesh: ballMesh, material: UnlitMaterial(color: UIColorCompat.rgb(SIMD3(0.95, 0.45, 0.05), alpha: 1)))
    }

    /// 点を、使い回す物に置く。足りなければ作り、余った物は隠す。
    private func show(_ positions: [SIMD3<Double>], in entities: inout [ModelEntity], mesh: MeshResource, material: UnlitMaterial) {
        while entities.count < positions.count {
            entities.append(makeEntity(mesh: mesh))
        }
        for (index, entity) in entities.enumerated() {
            guard index < positions.count else {
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            entity.position = SIMD3<Float>(positions[index])
            entity.model?.materials = [material]
        }
    }

    // MARK: - 部品

    private func makeEntity(mesh: MeshResource) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColorCompat.white(0.5))])
        entity.isEnabled = false
        root.addChild(entity)
        return entity
    }

    /// 高さ 1 の円柱を、2 点を結ぶ棒にする。
    private func place(_ entity: ModelEntity, from start: SIMD3<Double>, to end: SIMD3<Double>) {
        let length = simd_distance(start, end)
        guard length > 1e-4 else {
            entity.isEnabled = false
            return
        }
        entity.isEnabled = true
        entity.position = SIMD3<Float>((start + end) / 2)
        entity.scale = SIMD3(1, Float(length), 1)
        entity.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: SIMD3<Float>(simd_normalize(end - start)))
    }
}
