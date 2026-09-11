# Originates from the Waydroid Project

rompath=$(pwd)
vendor_path="vendor/extra"

function apply-patches
{
    ${vendor_path}/patches/apply-patches.sh
}

