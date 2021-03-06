#!/bin/sh

#mjson variables read

#platform info
boot_type=$(get_boot_media)

case "${boot_type}" in
    nand)
        echo "boot from ${boot_type}"
        echo "checking is no need"
        exit 0; #boot from nand, just exit 0
        ;;
    *)
        echo "boot from ${boot_type}";
        ;;
esac

if [ ! -b /dev/nanda ];then
    exit 1
fi

echo "nand test ioctl start"
nandrw "/dev/nanda"

if [ $? -ne 0 ];then
    echo "nand ioctl failed"
    exit 1
else
    echo "nand ioctl test ok"
    exit 0
fi
