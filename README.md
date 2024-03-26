# Crontab

This is a plugin for [Koha](http://koha-community.org) that simplifies the management of a koha instances local crontab.

We put the power in the hands of the user by exposing the local crontab to them as an administration tool plugin, allowing them to edit 
existing lines, schedules and environment as well as adding new jobs all from within the staff UI.

# Configuration

This plugin can accept some settings stored in the koha configuration file, inside the `config` block.

## koha_plugin_crontab_cronfile
`<koha_plugin_crontab_cronfile>/etc/cron.d/koha-mylibrary</koha_plugin_crontab_cronfile>`
By default the plugin will use the Koha user's crontab. If this option is set, it will use this file instead.

## koha_plugin_crontab_user_allowlist
`<koha_plugin_crontab_user_allowlist>1,2,3</koha_plugin_crontab_user_allowlist>`
This option, if set, will allow only the users whose borrowernumbers are listed to access the plugin
even if the patron has the admin plugins permission.

# Installation

## Enable the plugin system

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Add the pluginsdir to your apache PERL5LIB paths and koha-plack startup scripts PERL5LIB
* Restart your webserver

Once set up is complete you will need to alter your UseKohaPlugins system preference.

## Add dependencies

This plugin depends on the Config::Crontab perl module from CPAN. You will need to ask your system administrator to 
ensure it is available prior to downloading and installing the plugin package.

The package can be installed using apt:

`sudo apt install libconfig-crontab-perl`

## Download and install the plugin

The latest releases of this plugin can be obtained from the [release page](https://github.com/ptfs-europe/koha-plugin-crontab/releases) where you can download the relevant *.kpz file
