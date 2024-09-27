#!/bin/bash
set -e

VG_NAME=${1:-VG_data}
LV_NAME=${2:-data}

if [ -z "$VG_NAME" ] || [ -z "$LV_NAME" ]; then
    echo "Usage: $0 [Volume Group] [Logical Volume]"
    exit 1
fi

for h in $(ls /sys/class/scsi_host); do
  echo '- - -' > /sys/class/scsi_host/$h/scan
done

AVAILABLE_DISKS=($(lsblk -dpnlo name,type | grep -E 'disk' | awk '{print $1}'))

MOUNTED_PARTITIONS=($(lsblk -lpn | awk '/part/ {print $1}' | tr '\n' ' '))

# Loop through the available disks and try to add them to the volume group
for DISK in "${AVAILABLE_DISKS[@]}"; do
    # Check if the disk is a mounted partition
    # This is not ideal as potentially there could be a partition we would want to use on the same disk
    # However, very unlikely as we use whole disks for CCX
    if [[ ! " ${MOUNTED_PARTITIONS[@]} " =~ "${DISK}" ]]; then
        # Check if the disk is already encrypted
        if ! cryptsetup isLuks ${DISK} && ! pvdisplay "$DISK" > /dev/null 2>&1; then
            # Encrypted Volume
            EVOL=${DISK##*/}_crypt

            # Check if the directory exists, if not, create it
            KEY_DIR="/etc/ssl/ccx"
            if [ ! -d ${KEY_DIR} ]; then
              sudo mkdir -p ${KEY_DIR}
            fi

            # Generate a new disk encryption key if it is not exists
            KEY_FILE="$KEY_DIR/disk_key.pem"
            if [ ! -f ${KEY_FILE} ]; then
              openssl genpkey -algorithm RSA -out ${KEY_FILE}
            fi


            cryptsetup luksFormat -q --key-file  ${KEY_FILE} ${DISK}
            # Open the encrypted volume
            cryptsetup luksOpen --key-file  ${KEY_FILE} ${DISK} ${EVOL}
            # setup /etc/crypttab
            echo "${EVOL} UUID=$(blkid -s UUID -o value ${DISK}) ${KEY_FILE} luks" >> /etc/crypttab
            # Create a physical volume
            pvcreate "/dev/mapper/${EVOL}"
            # Check if volume group exists || if not, create it
            if ! vgdisplay "$VG_NAME" > /dev/null 2>&1; then
                vgcreate "$VG_NAME" "/dev/mapper/${EVOL}"
                # Create logical volume data
                lvcreate -l 100%VG "$VG_NAME" -n data
                # Create the filesystem
                blkid /dev/mapper/${VG_NAME}-data || mkfs.ext4 /dev/mapper/${VG_NAME}-data
            else
                # Extend the volume group
                vgextend "$VG_NAME" "/dev/mapper/${EVOL}"
            fi
        fi
    fi
done

# Extend the logical volume and resize the fs
lvextend -r -l +100%FREE "/dev/$VG_NAME/$LV_NAME"

# check for VG_data-data in /etc/fstab
if ! grep -q VG_data-data /etc/fstab; then
    echo "/dev/mapper/VG_data-data /data ext4 defaults,noatime 0 0" >> /etc/fstab
    mount /data
fi

#Taddam
echo "All available disks are added and the volume is extended successfully."

# Print final size of /data
SIZE_G=$(lvs /dev/$VG_NAME/$LV_NAME -o LV_SIZE --noheadings --units g --nosuffix | xargs printf "%.0f")
echo "FINAL_SIZE=[$SIZE_G]"

exit 0