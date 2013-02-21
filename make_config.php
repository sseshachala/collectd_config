<?php

require 'Mustache/Autoloader.php';
Mustache_Autoloader::register();

function configuration_for($json) {

    if (property_exists($json->defaults, "interval")) {
        $defaultinterval = $json->defaults->interval;
    } else {
        $defaultinterval = "60";
    }
    $data = array("interval" => $defaultinterval,
        "host" => $json->server->host,
        "username" => $json->server->username,
        "password" => $json->server->password,
        "load" => array(),
        "plugins" => array()
    );

    foreach ($json->plugins as $plugin) {
        $name = $plugin->name;
        if (property_exists($plugin, "interval")) {
            $interval = $plugin->interval;
        } else {
            $interval = $defaultinterval;
        }
        array_push($data["load"], array("plugname" => $name, "pluginterval" => $interval));
        $settings = array();
        foreach ($plugin->settings as $k => $v) {
            array_push($settings, array("setname" => $k, "setval" => $v));
        }
        array_push($data["plugins"], array("plugname" => $name, "settings" => $settings));
    }
    $m = new Mustache_Engine;
    echo $m->render(file_get_contents("template.txt"), $data);
}

?>
