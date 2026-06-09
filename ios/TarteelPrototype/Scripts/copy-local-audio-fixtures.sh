#!/bin/sh
set -eu

resource_dir_name="local_audio"
destination_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/${resource_dir_name}"

copy_if_present() {
    source_dir="$1"
    if [ -d "$source_dir" ]; then
        rm -rf "$destination_dir"
        mkdir -p "$destination_dir"
        find "$source_dir" -maxdepth 1 -type f -name "*.wav" -exec cp {} "$destination_dir" \;
        copied_count=$(find "$destination_dir" -maxdepth 1 -type f -name "*.wav" | wc -l | tr -d " ")
        if [ "$copied_count" != "0" ]; then
            echo "Copied ${copied_count} local audio replay fixture(s) from ${source_dir}"
            exit 0
        fi
    fi
}

copy_if_present "${SRCROOT}/../../fixtures/local_audio"
copy_if_present "${SRCROOT}/../../../../fixtures/local_audio"

rm -rf "$destination_dir"
echo "Local audio replay fixtures not found; developer replay launch arguments will require an absolute audio path."
