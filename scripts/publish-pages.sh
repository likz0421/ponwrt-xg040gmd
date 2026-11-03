#!/bin/bash
# 把本地目录发到 GitHub Pages（gh-pages 分支）的指定子树里，并且**只替换自己那一块**。
#
# 为什么不是 git init + push -f：两条产品线共用同一个 Pages 站点
# （https://<owner>.github.io/<repo>/）。XG 发在根路径，TYFZA1 发在 tyfza1/ 下；
# 谁用 `push -f` 重建整棵 gh-pages，就把对方刚发好的索引抹掉了 ——
# 表现是对方设备的 apk update 突然全线 404，而两边作业都是绿的。
#
# 用法（成对传：本地源目录 → gh-pages 里的子路径）：
#   PAGES_GIT_URL=https://x-access-token:$TOKEN@github.com/OWNER/REPO.git \
#   PAGES_WORK="$RUNNER_TEMP/pages" \
#     bash publish-pages.sh <src1> <dstrel1> [<src2> <dstrel2> ...]
# 例：publish-pages.sh bin/targets/rtl9617c/generic/packages tyfza1/targets/rtl9617c/generic/packages
set -euo pipefail
[ $(( $# % 2 )) = 0 ] && [ "$#" -ge 2 ] || {
	echo "::error::参数必须成对：<本地目录> <Pages 子路径> …"; exit 1; }
: "${PAGES_GIT_URL:?未设置 PAGES_GIT_URL}"
TMP="${PAGES_WORK:?未设置 PAGES_WORK}"

rm -rf "$TMP"; mkdir -p "$TMP"
git -C "$TMP" init -q
git -C "$TMP" remote add origin "$PAGES_GIT_URL"
if git -C "$TMP" fetch -q --depth 1 origin gh-pages 2>/dev/null; then
	git -C "$TMP" -c advice.detachedHead=false checkout -q -B gh-pages FETCH_HEAD
	echo "取回现有 gh-pages：$(git -C "$TMP" rev-list --count HEAD) 个提交，$(find "$TMP" -type f -not -path '*/.git/*' | wc -l) 个文件（别的设备子树会保留）"
else
	git -C "$TMP" checkout -q -B gh-pages
	echo "gh-pages 分支还不存在，本次从头建"
fi

while [ "$#" -ge 2 ]; do
	src="$1"; dst="$2"; shift 2
	[ -d "$src" ] || { echo "::error::本地源目录不存在：$src"; exit 1; }
	case "$dst" in
		''|/*|*..*) echo "::error::Pages 子路径不合法：[$dst]"; exit 1 ;;
	esac
	mkdir -p "$TMP/$dst"
	# 只清空自己这一块，别的一律不动
	find "$TMP/$dst" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
	cp -a "$src/." "$TMP/$dst/"
	echo "  $src → $dst/ ：$(find "$TMP/$dst" -type f | wc -l) 个文件，$(du -sh "$TMP/$dst" | cut -f1)"
done

git -C "$TMP" add -A -f
if git -C "$TMP" diff --cached --quiet; then
	echo "gh-pages 内容没变化，跳过提交"
else
	git -C "$TMP" -c user.name=github-actions \
		-c user.email=41898282+github-actions[bot]@users.noreply.github.com \
		commit -q -m "apk repo: run ${GITHUB_RUN_ID:-local}"
	# 我们是 --depth 1 取的 gh-pages：正常推送只上传新提交（远端已有全部祖先），
	# 万一这时远端又被另一条产品线推前了，就取深一点、把我们的提交重放到最新之上再推。
	if ! git -C "$TMP" -c credential.helper= push -q origin gh-pages:gh-pages; then
		echo "首次推送没成功（多半是远端刚被另一条线推前），取深历史后重试"
		git -C "$TMP" fetch -q --deepen 20 origin gh-pages || true
		git -C "$TMP" rebase -q FETCH_HEAD || { echo "::error::与远端 gh-pages 冲突，需要人工看"; exit 1; }
		git -C "$TMP" -c credential.helper= push -q origin gh-pages:gh-pages
	fi
	echo "已推送 gh-pages（推送后 Pages 还要构建一会儿才可见）"
fi
