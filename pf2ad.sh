#!/bin/sh

VERSION='20211004002'
SQUID_VERSION="0.4.45_5"

if [ -f "/etc/samba.patch.version" ]; then
    if [ "$(cat /etc/samba.patch.version)" = "$VERSION" ]; then
        if ! [ -z "$TERM" ]; then
            dialog \
                --title 'pf2ad install' \
                --msgbox 'Changes have been applied!'  \
            6 40
            resp=$(
            dialog --stdout \
                --title 'pf2ad Install' \
                --menu 'Do you want:' \
                0 0 0 \
                reinstall       'Force a reinstall of script' \
                remove          'Remove the configurations of script' \
                exit            'Exit and does nothing')
            case $resp in
                "exit"     ) exit 0;;
                "remove"   ) echo "Not implemented yet"; exit 0;;
                "reinstall") continue;;
            esac
        else
            echo "NOTICE: Changes have been applied!"
            exit 0
        fi
    fi
fi

# Verifica versao pfSense
if [ "$(cat /etc/version)" != "2.5.2-RELEASE" ]; then
    echo "ERROR: You need the pfSense version 2.5.2 to apply this script"
    exit 2
fi

ARCH="$(uname -p)"

ASSUME_ALWAYS_YES=YES
export ASSUME_ALWAYS_YES

/usr/sbin/pkg bootstrap
/usr/sbin/pkg update

# Lock packages necessary
LOCK_PKGS="pkg"
for LP in $LOCK_PKGS; do
  /usr/sbin/pkg lock $LP
done

mkdir -p /usr/local/etc/pkg/repos
cat <<EOF > /usr/local/etc/pkg/repos/pf2ad.conf
pf2ad: {
    url: "https://pkg.pf2ad.com/pfsense/2.5.2/amd64-n/",
    mirror_type: "https",
    enabled: yes,
    priority: 100
}
EOF

# Remove old samba44
if [ "$(/usr/sbin/pkg info | grep samba44)" ]; then
  /usr/sbin/pkg unlock samba44
  /usr/sbin/pkg remove samba44 ldb
fi

if [ "$(/usr/sbin/pkg info | grep samba48)" ]; then
  /usr/sbin/pkg unlock samba48
  /usr/sbin/pkg remove samba48 ldb
fi

if [ "$(/usr/sbin/pkg info | grep samba410)" ]; then
  /usr/sbin/pkg unlock samba410
  /usr/sbin/pkg remove samba410 ldb tdb
fi

if [ "$(/usr/sbin/pkg info | grep samba411)" ]; then
  /usr/sbin/pkg unlock samba411
  /usr/sbin/pkg remove samba411 ldb tdb
fi

if [ "$(/usr/sbin/pkg info | grep samba412)" ]; then
  /usr/sbin/pkg unlock samba412
  /usr/sbin/pkg remove samba412 ldb tdb
fi

/usr/sbin/pkg update -r pf2ad
/usr/sbin/pkg install -r pf2ad net/samba413 2> /dev/null
/usr/sbin/pkg lock samba413

for LP in $LOCK_PKGS; do
  /usr/sbin/pkg unlock $LP
done

rm -rf /usr/local/etc/pkg/repos/pf2ad.conf
/usr/sbin/pkg update

mkdir -p /var/db/samba4/winbindd_privileged
chown -R :proxy /var/db/samba4/winbindd_privileged
chmod -R 0750 /var/db/samba4/winbindd_privileged

fetch -o /usr/local/pkg/samba.inc -q "https://pf2ad.com/download.php?key=fc4953fc35b18035a22aed7be2680ce943a1f736&version=2.5.2&file=samba.inc"
fetch -o /usr/local/pkg/samba.xml -q "https://pf2ad.com/download.php?key=fc4953fc35b18035a22aed7be2680ce943a1f736&version=2.5.2&file=samba.xml"
fetch -o /usr/local/www/diag_samba.php -q "https://pf2ad.com/download.php?key=fc4953fc35b18035a22aed7be2680ce943a1f736&version=2.5.2&file=diag_samba.php"

/usr/local/bin/php <<EOF
<?php
require_once("functions.inc");
\$samba = false;
foreach (\$config['installedpackages']['service'] as \$item) {
  if ('samba' == \$item['name']) {
    \$samba = true;
    break;
  }
}
if (\$samba == false) {
    \$config['installedpackages']['service'][] = array(
      'name' => 'samba',
      'rcfile' => 'samba.sh',
      'executable' => 'smbd',
      'description' => 'Samba daemon'
  );
}
\$samba = false;
foreach (\$config['installedpackages']['menu'] as \$item) {
  if ('Samba (AD)' == \$item['name']) {
    \$samba = true;
    break;
  }
}
if (\$samba == false) {
  \$config['installedpackages']['menu'][] = array(
    'name' => 'Samba (AD)',
    'section' => 'Services',
    'url' => '/pkg_edit.php?xml=samba.xml'
  );
}
write_config("Write install samba configuration");
exit(0);
?>
EOF

# always try install or update squid
if [ "$(/usr/sbin/pkg info -q | grep pfSense-pkg-squid-)" ]; then
    if [ "$(pkg info -i pfSense-pkg-squid | grep Version | awk '{ print $3 }')" != "${SQUID_VERSION}" ]; then 
        /usr/sbin/pkg install -f -r pfSense pfSense-pkg-squid
    fi
else
    /usr/sbin/pkg install -r pfSense pfSense-pkg-squid
fi

cd /usr/local/pkg
if [ "$(cat squid.inc squid_auth.xml squid_js.inc | md5)" != "056e6b351429bcd40aea82b78a3c8ded" ]; then
    fetch -o - -q "https://pf2ad.com/download.php?key=fc4953fc35b18035a22aed7be2680ce943a1f736&version=2.5.2&file=samba4-squid.diff" | patch -s -p0
fi

if [ ! -f "/usr/local/etc/smb4.conf" ]; then
    touch /usr/local/etc/smb4.conf
fi
cp -f /usr/local/bin/ntlm_auth /usr/local/libexec/squid/ntlm_auth

/etc/rc.d/ldconfig restart

echo "$VERSION" > /etc/samba.patch.version


