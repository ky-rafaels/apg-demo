#!/bin/bash

VG=ubuntu--vg

#Create logical volumes to be used by k8s PV's
sudo lvcreate -L 30G -n 10000001 $VG
sudo lvcreate -L 30G -n 10000002 $VG
sudo lvcreate -L 30G -n 10000003 $VG
sudo lvcreate -L 30G -n 10000004 $VG
sudo lvcreate -L 50G -n 11000001 $VG
sudo lvcreate -L 50G -n 11000002 $VG
sudo lvcreate -L 50G -n 11100001 $VG
sudo lvcreate -L 100G -n 10000005 $VG
sudo lvcreate -L 100G -n 10000006 $VG
sudo lvcreate -L 100G -n 10000007 $VG

#Make filesystem for logical volumes
sudo mkfs -F -t ext4 /dev/mapper/$VG-10000001
sudo mkfs -F -t ext4 /dev/mapper/$VG-10000002
sudo mkfs -F -t ext4 /dev/mapper/$VG-10000003
sudo mkfs -F -t ext4 /dev/mapper/$VG-10000004
sudo mkfs -F -t ext4 /dev/mapper/$VG-11000001
sudo mkfs -F -t ext4 /dev/mapper/$VG-11000002
sudo mkfs -F -t ext4 /dev/mapper/$VG-11100001
sudo mkfs -F -t ext4 /dev/mapper/$VG-10000005
sudo mkfs -F -t ext4 /dev/mapper/$VG-10000006
sudo mkfs -F -t ext4 /dev/mapper/$VG-10000007

#Make base mount directory under /mnt
sudo mkdir -p /mnt/disks

#Mount 11G volumes
DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-10000001)
sudo mkdir /mnt/disks/10000001
sudo mount -t ext4 /dev/mapper/$VG-10000001 /mnt/disks/10000001
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-10000001` /mnt/disks/10000001 ext4 defaults 0 0 | sudo tee -a /etc/fstab

DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-10000002)
sudo mkdir /mnt/disks/10000002
sudo mount -t ext4 /dev/mapper/$VG-10000002 /mnt/disks/10000002
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-10000002` /mnt/disks/10000002 ext4 defaults 0 0 | sudo tee -a /etc/fstab

DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-10000003)
sudo mkdir /mnt/disks/10000003
sudo mount -t ext4 /dev/mapper/$VG-10000003 /mnt/disks/10000003
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-10000003` /mnt/disks/10000003 ext4 defaults 0 0 | sudo tee -a /etc/fstab

DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-10000004)
sudo mkdir /mnt/disks/10000004
sudo mount -t ext4 /dev/mapper/$VG-10000004 /mnt/disks/10000004
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-10000004` /mnt/disks/10000004 ext4 defaults 0 0 | sudo tee -a /etc/fstab

#Mount 35G volumes
DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-11000001)
sudo mkdir /mnt/disks/11000001
sudo mount -t ext4 /dev/mapper/$VG-11000001 /mnt/disks/11000001
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-11000001` /mnt/disks/11000001 ext4 defaults 0 0 | sudo tee -a /etc/fstab

DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-11000002)
sudo mkdir /mnt/disks/11000002
sudo mount -t ext4 /dev/mapper/$VG-11000002 /mnt/disks/11000002
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-11000002` /mnt/disks/11000002 ext4 defaults 0 0 | sudo tee -a /etc/fstab

#Mount 105G volumes
DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-11100001)
sudo mkdir /mnt/disks/11100001
sudo mount -t ext4 /dev/mapper/$VG-11100001 /mnt/disks/11100001
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-11100001` /mnt/disks/11100001 ext4 defaults 0 0 | sudo tee -a /etc/fstab

DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-10000005)
sudo mkdir /mnt/disks/10000005
sudo mount -t ext4 /dev/mapper/$VG-10000005 /mnt/disks/10000005
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-10000005` /mnt/disks/10000005 ext4 defaults 0 0 | sudo tee -a /etc/fstab

DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-10000006)
sudo mkdir /mnt/disks/10000006
sudo mount -t ext4 /dev/mapper/$VG-10000006 /mnt/disks/10000006
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-10000006` /mnt/disks/10000006 ext4 defaults 0 0 | sudo tee -a /etc/fstab

DISK_UUID=$(sudo blkid -s UUID -o value blkid /dev/mapper/$VG-10000007)
sudo mkdir /mnt/disks/10000007
sudo mount -t ext4 /dev/mapper/$VG-10000007 /mnt/disks/10000007
echo UUID=`sudo blkid -s UUID -o value /dev/mapper/$VG-10000007` /mnt/disks/10000007 ext4 defaults 0 0 | sudo tee -a /etc/fstab