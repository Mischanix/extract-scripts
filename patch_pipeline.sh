#!/bin/zsh

set -e

BASEDIR="$(readlink -f $(dirname $0))"
BUILD="$1"

isnum='^[0-9]+$'
if ! [[ $BUILD =~ $isnum ]]; then
	>&2 echo "USAGE: $0 [BUILD]"
	exit 1
fi

# Base directory for large data files
DATADIR="/mnt/home/ngdp"

# Base build directory from extract-scripts
BUILDDIR="$BASEDIR/build"

# Directory storing the 'hsb' blte config
HSBDIR="$DATADIR/hsb"

# Extraction path for 'hsb' blte
NGDP_OUT="$HSBDIR/out"

# Directory storing the build data files
HSBUILDDIR="$DATADIR/data/ngdp/hsb/$BUILD"

# Directory that contains card textures
CARDARTDIR="$BUILDDIR/card-art"

# HearthstoneJSON git repository
HEARTHSTONEJSON_GIT="$BUILDDIR/HearthstoneJSON"

# HearthstoneJSON file generator
HEARTHSTONEJSON_BIN="$HEARTHSTONEJSON_GIT/generate.sh"

# HearthstoneJSON generated files directory
HSJSONDIR="$HOME/projects/HearthstoneJSON/build/html/v1/$BUILD"

# Symlink file for extracted data
EXTRACTED_BUILD_DIR="$BUILDDIR/extracted/$BUILD"

# Patch downloader
BLTE_BIN="$HOME/bin/blte.exe"

# Autocommit script
COMMIT_BIN="$BASEDIR/commit.sh"

# Card texture extraction/generation script
TEXTUREGEN_BIN="$HEARTHSTONEJSON_GIT/generate_card_textures.py"

# Card texture generate script
TEXTURESYNC_BIN="$HEARTHSTONEJSON_GIT/generate.sh"

# Smartdiff generation script
SMARTDIFF_BIN="$BASEDIR/smartdiff_cardxml.py"

# Smartdiff output file
SMARTDIFF_OUT="$HOME/smartdiff-$BUILD.txt"

# hscode/hsdata git repositories
HSCODE_GIT="$BASEDIR/hscode.git"
HSDATA_GIT="$BASEDIR/hsdata.git"

# CardDefs.xml path for the build
CARDDEFS_XML="$HSDATA_GIT/CardDefs.xml"

# Python requirements for the various scripts
REQUIREMENTS_TXT="$BASEDIR/requirements.txt"


function upgrade_venv() {
	if [[ -z $VIRTUAL_ENV ]]; then
		>&2 echo "Must be run from within a virtualenv"
		exit 1
	else
		pip install --upgrade pip
		pip install -r "$REQUIREMENTS_TXT" --upgrade --no-cache-dir
	fi
}


function update_repositories() {
	echo "Updating repositories"
	repos=("$BASEDIR" "$HEARTHSTONEJSON_GIT" "$HSDATA_GIT" "$HSCODE_GIT")

	if [[ ! -d "$HEARTHSTONEJSON_GIT" ]]; then
		git clone git@github.com:HearthSim/HearthstoneJSON.git "$HEARTHSTONEJSON_GIT"
	fi

	if [[ ! -d "$HSDATA_GIT" ]]; then
		git clone git@github.com:HearthSim/hsdata.git "$HSDATA_GIT"
	fi

	if [[ ! -d "$HSCODE_GIT" ]]; then
		git clone git@github.com:HearthSim/hscode.git "$HSCODE_GIT"
	fi

	for repo in $repos; do
		git -C "$repo" pull
	done
}


function check_commit_sh() {
	if ! grep -q "$BUILD" "$COMMIT_BIN"; then
		>&2 echo "$BUILD is not present in $COMMIT_BIN. Aborting."
		exit 3
	fi
}


function prepare_patch_directories() {
	echo "Preparing patch directories"
	if [[ -e $EXTRACTED_BUILD_DIR ]]; then
		echo "$EXTRACTED_BUILD_DIR already exists, not overwriting."
	else
		if [[ -d $HSBUILDDIR ]]; then
			echo "$HSBUILDDIR already exists... skipping download checks."
		else
			if ! [[ -d "$NGDP_OUT" ]]; then
				>&2 echo "No "$NGDP_OUT" directory. Run cd $HSBDIR && $BLTE_BIN"
				exit 2
			fi
			echo "Moving $NGDP_OUT to $HSBUILDDIR"
			mv "$NGDP_OUT" "$HSBUILDDIR"
		fi
		echo "Creating symlink to build in $EXTRACTED_BUILD_DIR"
		ln -s -v "$HSBUILDDIR" "$EXTRACTED_BUILD_DIR"
	fi
}


function extract_and_decompile() {
	# Panic? cardxml_raw_extract.py can extract the raw carddefs
	# Coupled with a manual process_cardxml.py --raw, can gen CardDefs.xml

	if ! git -C "$HSDATA_GIT" rev-parse "$BUILD" &>/dev/null; then
		echo "Extracting and decompiling the build"

		make --directory="$BASEDIR" -B \
			"$EXTRACTED_BUILD_DIR/" \
			"$EXTRACTED_BUILD_DIR/Hearthstone_Data/Managed/Assembly-CSharp.dll" \
			"$EXTRACTED_BUILD_DIR/Hearthstone_Data/Managed/Assembly-CSharp-firstpass.dll"

		echo "Generating git repositories"
		"$COMMIT_BIN" "$BUILD"

		echo "Pushing to GitHub"
		git -C "$HSDATA_GIT" push --follow-tags -f
		git -C "$HSCODE_GIT" push --follow-tags -f
	else
		echo "Tag $BUILD already present in $HSDATA_GIT - skipping core build generation."
	fi
}


function generate_smartdiff() {
	git -C "$HSDATA_GIT" show "$BUILD:CardDefs.xml" > /tmp/new.xml
	git -C "$HSDATA_GIT" show "$BUILD~:CardDefs.xml" > /tmp/old.xml

	echo "Generating smartdiff"
	"$SMARTDIFF_BIN" "/tmp/old.xml" "/tmp/new.xml" > "$SMARTDIFF_OUT"
	echo "Generated smartdiff in $SMARTDIFF_OUT"
	rm /tmp/new.xml /tmp/old.xml
}


function update_hearthstonejson() {
	echo "Updating HearthstoneJSON"
	if [[ -e $HSJSONDIR ]]; then
		echo "HearthstoneJSON is up-to-date."
	else
		"$HEARTHSTONEJSON_BIN" "$BUILD"
	fi
}


function extract_card_textures() {
	echo "Extracting card textures"
	"$TEXTUREGEN_BIN" "$HSBUILDDIR/Data/Win/"{card,shared}*.unity3d --outdir="$CARDARTDIR" --skip-existing
	"$TEXTURESYNC_BIN" sync-textures "$CARDARTDIR"
}


function main() {
	upgrade_venv
	update_repositories
	check_commit_sh
	prepare_patch_directories
	extract_and_decompile
	generate_smartdiff
	extract_card_textures
	update_hearthstonejson

	echo "Build $BUILD completed"
}


main "$@"
