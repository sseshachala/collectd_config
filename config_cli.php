<?php
require 'make_config.php';

echo configuration_for(json_decode(file_get_contents($argv[1])));
echo "\n\n";

?>
