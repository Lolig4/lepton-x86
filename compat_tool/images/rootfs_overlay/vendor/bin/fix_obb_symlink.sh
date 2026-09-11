#!/system/bin/sh

APP_ID=$1

APP_PATH="$(pm path ${APP_ID} | sed "s/^package://g" | sed "s/\/base.apk$//g")";

local OBB_INNER_PATH="${APP_PATH}"

# If the obb dir is empty we use the main directory
rmdir "${OBB_INNER_PATH}/obb" || true

if [[ -d "${OBB_INNER_PATH}/obb" ]]; then
    OBB_INNER_PATH="${APP_PATH}/obb"
fi
rm -f /data/media/0/Android/obb/${APP_ID} || true
rmdir /data/media/0/Android/obb/${APP_ID} || true

ln -sv ${OBB_INNER_PATH} /data/media/0/Android/obb/${APP_ID};
