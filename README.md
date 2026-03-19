# PWPsetup

## Proxmox Windows Powershell setup

This tool **clones VMs from a template** and **sets them up with powershell scripts** of your choice (stored in a **cloud storage**) in **sequential order** (as instructed in the config file), all while **handling reboots with it's marker-based system**. 

## Components:

0) Proxmox



1) PWPsetup bash script downloaded onto proxmox

2) Configuration file for the PWPsetup bash script downloaded onto proxmox and **edited in accordance with your project and scripts**

3) Your powershell scripts uploaded to a cloud storage of your choice

4) A Windows template with [QEMU guest agent](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/?C=M;O=D) running on it



5) Any dependencies you need for your setup (UCS AD, etc.)



## IMPORTANT: Requirements for your powershell scripts:

Your powershell scripts **must not reboot by themselves**, instead:

Powershell scripts **must produce a .done marker file after completion** (New-Item -ItemType File -Path "C:\automation\host1script0.ps1.done" -Force | Out-Null). **The name of the marker must always be the same as the name of the script for which the marker is created, for example the marker name for host1script0.ps1 would be host1script0.ps1.done. Overall, the script names must always remain the same between the config, the marker names and obviously the actual file names.** So please pay attention to that!


## How to use:

1. Create the Windows template with QEMU guest agent running

2. Download the PWPsetup bash script and config file

3. Upload your powershell scripts to your cloud storage of choice

4. Edit the configuration file for PWPsetup in accordance with your setup (set the amount of servers, script names and script links, etc.)

5. Create VMs with dependencies if they are required for your setup

6. Run the script.
