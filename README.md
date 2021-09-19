# crate-add
Are you annoyed that you have to write to / from a toml file to manage dependency libraries? When you add a crate do you just use the latest version?

same.

crate-add is a bash script to add and remove dependencies for rust projects. Does a lookup and adds the dependency to the toml file and leaves installation / updating to cargo.

Currently only installs most recent version of the crate, can look into supporting named versions in future.

install with 
``` sh
sudo bash -c "install -bm 755 <(wget -qO- 'https://raw.githubusercontent.com/croconut/crate-add/master/crate-add.sh')  /usr/local/bin/crate-add"
```
