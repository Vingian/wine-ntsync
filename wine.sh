#!/bin/bash

#GH_REPO=''
#GH_TOKEN=''

STAGING_EXCLUDE='-W ntdll-ForceBottomUpAlloc'

WINE_VERSION=($(curl -s 'https://gitlab.winehq.org/api/v4/projects/5/releases' | jq -r '.[0].tag_name' 2>/dev/null | grep -o '[0-9.]*'))
STAGING_VERSION=($(curl -s 'https://gitlab.winehq.org/api/v4/projects/231/repository/tags' | jq -r '.[0].name' 2>/dev/null | grep -o '[0-9.]*'))

[ ${#WINE_VERSION[@]} -gt 1 ] && WINE_RC_VERSION="${WINE_VERSION[1]}" || WINE_RC_VERSION='9999'
[ ${#WINE_VERSION[@]} -ge 1 ] && WINE_VERSION="${WINE_VERSION[0]}" || WINE_VERSION=''
[ ${#STAGING_VERSION[@]} -gt 1 ] && STAGING_RC_VERSION="${STAGING_VERSION[1]}" || STAGING_RC_VERSION='9999'
[ ${#STAGING_VERSION[@]} -ge 1 ] && STAGING_VERSION="${STAGING_VERSION[0]}" || STAGING_VERSION=''

[[ -z "$WINE_VERSION" || -z "$STAGING_VERSION" ]] && exit 0

WINE_VERSION_TAG=$([ "$WINE_RC_VERSION" != '9999' ] && echo "${WINE_VERSION}-rc${WINE_RC_VERSION}" || echo "$WINE_VERSION")
STAGING_VERSION_TAG=$([ "$STAGING_RC_VERSION" != '9999' ] && echo "${STAGING_VERSION}-rc${STAGING_RC_VERSION}" || echo "$STAGING_VERSION")

if [[ -n "$GH_REPO" && -n "$GH_TOKEN" ]]; then
	HAVE_WINE_VERSION=$([ "$(curl -s -w '%{http_code}' -o /dev/null "https://x-access-token:${GH_TOKEN}@api.github.com/repos/${GH_REPO}/git/refs/tags/wine-${WINE_VERSION_TAG}")" -ne 404 ] && echo 'y' || echo '')
	HAVE_STAGING_VERSION=$([ "$(curl -s -w '%{http_code}' -o /dev/null "https://x-access-token:${GH_TOKEN}@api.github.com/repos/${GH_REPO}/git/refs/tags/wine-${STAGING_VERSION_TAG}-staging")" -ne 404 ] && echo 'y' || echo '')
fi

if [ $(echo -e "${WINE_VERSION_TAG}\n${STAGING_VERSION_TAG}"|sort -V|tail -1) == "$STAGING_VERSION_TAG" ] && [[ -z "$HAVE_WINE_VERSION" || -z "$HAVE_STAGING_VERSION" ]]; then
	rm -rf {wine,tkg-wine,staging-wine,tkg-staging-wine,wine-staging,wine-tkg-git}

	git clone -b "wine-${WINE_VERSION_TAG}" 'https://gitlab.winehq.org/wine/wine.git' || exit 0
	pushd wine
	git -c advice.detachedHead=false checkout "wine-${WINE_VERSION_TAG}"
	git config user.name 'github-actions[bot]'
	git config user.email 'github-actions[bot]@users.noreply.github.com'
	[[ -n "$GH_REPO" && -n "$GH_TOKEN" ]] && git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git" || git remote remove origin
	popd

	git clone -b "v${STAGING_VERSION_TAG}" 'https://gitlab.winehq.org/wine/wine-staging.git' || exit 0
	cp -r wine staging-wine
	./wine-staging/staging/patchinstall.py DESTDIR=staging-wine -a $STAGING_EXCLUDE

	git clone 'https://github.com/Frogging-Family/wine-tkg-git.git' || exit 0
	pushd wine-tkg-git/wine-tkg-git || exit 0
	sed -i '/_build_in_tmpfs=/s/true/false/' non-makepkg-build.sh
	sed -i '/--mirror/s/^\(\s*\)/\1#/' non-makepkg-build.sh
	sed -i '/-B makepkg/s/^\(\s*\)/\1#/' non-makepkg-build.sh
	sed -i '/Wine staging update and checkout/,/rm -rf.*git clone/s/^\(\s*\)/\1#/' non-makepkg-build.sh
	sed -i '/Wine update and checkout/,/rm -rf.*git clone/s/^\(\s*\)/\1#/' non-makepkg-build.sh
	sed -i 's/_plain_version=""/_plain_version="wine-'"${WINE_VERSION_TAG}"'"/' customization.cfg
	sed -i 's/_staging_version=""/_staging_version="v'"${STAGING_VERSION_TAG}"'"/' customization.cfg
 	sed -i '/_use_fastsync=/s/true/false/' customization.cfg
 	sed -i '/_use_ntsync=/s/false/true/' customization.cfg
  	sed -i '/_use_esync=/s/true/false/' customization.cfg
   	sed -i '/_use_fsync=/s/true/false/' customization.cfg
	sed -i '/_proton_fs_hack=/s/false/true/' customization.cfg
	sed -i '/_win10_default=/s/false/true/' customization.cfg
	sed -i '/_use_josh_flat_theme=/s/true/false/' customization.cfg
	sed -i '/_nomakepkg_dependency_autoresolver=/s/true/false/' customization.cfg
	sed -i '/_NOCOMPILE=/s/false/true/' wine-tkg-profiles/advanced-customization.cfg
 	sed -i '$a\\n_staging_userargs="${_staging_userargs:+$_staging_userargs }'"${STAGING_EXCLUDE}"'"' wine-tkg-profiles/advanced-customization.cfg
	mkdir src
	popd

	if [ -z "$HAVE_WINE_VERSION" ]; then
		cp -r wine-staging wine-tkg-git/wine-tkg-git/src/wine-staging-git
		cp -r wine wine-tkg-git/wine-tkg-git/src/wine-git
		pushd wine-tkg-git/wine-tkg-git
		sed -i '/_use_staging=/s/true/false/' customization.cfg
		yes "" | ./non-makepkg-build.sh || exit 0
  		grep -q ' FAILED ' prepare.log >/dev/null 2>&1 && exit 0
		popd
		mv wine-tkg-git/wine-tkg-git/src/wine-git tkg-wine
		rm -rf wine-tkg-git/wine-tkg-git/src/*
	fi

	cp -r wine-staging wine-tkg-git/wine-tkg-git/src/wine-staging-git
	cp -r wine wine-tkg-git/wine-tkg-git/src/wine-git
	pushd wine-tkg-git/wine-tkg-git
	sed -i '/_use_staging=/s/false/true/' customization.cfg
	yes "" | ./non-makepkg-build.sh || exit 0
 	grep -q ' FAILED ' prepare.log >/dev/null 2>&1 && exit 0
	popd
	mv wine-tkg-git/wine-tkg-git/src/wine-git tkg-staging-wine
	rm -rf wine-tkg-git/wine-tkg-git/src/*

	if [ -z "$HAVE_WINE_VERSION" ]; then
 		pushd wine
		[[ -n "$GH_REPO" && -n "$GH_TOKEN" ]] && git push origin "wine-${WINE_VERSION_TAG}"
		popd

 		pushd tkg-wine
		git commit -a -m 'TKG...'
		git tag "wine-${WINE_VERSION_TAG}-tkg"
		[[ -n "$GH_REPO" && -n "$GH_TOKEN" ]] && git push origin "wine-${WINE_VERSION_TAG}-tkg"
		popd
	fi

	pushd staging-wine
	git commit -a -m 'Staging...'
	git tag "wine-${STAGING_VERSION_TAG}-staging"
	[[ -n "$GH_REPO" && -n "$GH_TOKEN" ]] && git push origin "wine-${STAGING_VERSION_TAG}-staging"
	popd

	pushd tkg-staging-wine
	git commit -a -m 'Staging TKG...'
	git tag "wine-${STAGING_VERSION_TAG}-staging-tkg"
	[[ -n "$GH_REPO" && -n "$GH_TOKEN" ]] && git push origin "wine-${STAGING_VERSION_TAG}-staging-tkg"
	popd
fi