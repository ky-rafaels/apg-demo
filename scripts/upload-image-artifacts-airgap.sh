#!/bin/bash
# Ensure you are in unpacked airgap bundle 
# nkp create package-bundle ubuntu-22.04 --artifacts-directory image-artifacts/

# TEMP Create an override dir for cloud-init fix
mkdir override

nkp upload image-artifacts \
--artifacts-directory ./image-artifacts \
--ssh-host 192.168.1.46 \
--ssh-username nutanix \
--ssh-private-key-file /Users/kylerafaels/.ssh/nkp-control \
--to-directory override

# Add ansible task to install cloud-init, temporary fix 
cat override/playbooks/upload-artifacts.yaml | tail -14
- hosts: all
  name: install cloud-init
  gather_facts: false
  become: true
  tasks:
  - name: Install cloud-init from local offline repo
    ansible.builtin.command:
      cmd: >-
        dnf install -y
        --repofrompath="local,/opt/dkp/packages/offline-repo"
        --repo="local"
        --nogpgcheck
        cloud-init
    become: true

# Upload artifacts
nkp upload image-artifacts \
--artifacts-directory ./image-artifacts \
--ssh-host 192.168.1.46 \
--ssh-username nutanix \
--ssh-private-key-file /Users/kylerafaels/.ssh/nkp-control \
--from-directory override