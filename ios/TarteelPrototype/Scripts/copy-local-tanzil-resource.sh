#!/bin/sh
set -eu

resource_name="quran-simple-clean.txt"
destination_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
destination_path="${destination_dir}/${resource_name}"

copy_if_present() {
    source_path="$1"
    if [ -f "$source_path" ]; then
        mkdir -p "$destination_dir"
        cp "$source_path" "$destination_path"
        echo "Copied local Tanzil Quran text from ${source_path}"
        exit 0
    fi
}

copy_if_present "${SRCROOT}/../../data/tanzil/${resource_name}"
copy_if_present "${SRCROOT}/../../../../data/tanzil/${resource_name}"

rm -f "$destination_path"
echo "Local Tanzil Quran text not found; CoreML local Quran session will use fallback corpus."
