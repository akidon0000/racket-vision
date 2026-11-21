.PHONY: setup

# apm のインストールと、Agent Skills の展開。スキルの正本は .apm/skills/、展開先（.claude/skills/ など）は git に入れない。
setup:
	brew install apm
	apm install
