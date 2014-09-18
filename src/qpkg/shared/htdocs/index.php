<?php
$filename = "./config.conf";
$memStep = 256;
$memDefault = 512;
$memTotal = ceil(round(exec("awk '/^MemTotal:/{print $2}' /proc/meminfo") / 1024, 0) / $memStep) * $memStep;
$eth0_addr = exec("/sbin/ifconfig eth0 | awk '/addr:/{print $2}' | cut -f2 -d:");
$eth1_addr = exec("/sbin/ifconfig eth1 | awk '/addr:/{print $2}' | cut -f2 -d:");
$bond0_addr = exec("/sbin/ifconfig bond0 | awk '/addr:/{print $2}' | cut -f2 -d:");
$wlan0_addr = exec("/sbin/ifconfig wlan0 | awk '/addr:/{print $2}' | cut -f2 -d:");
// Save posted data
$config = array();
if(isset($_POST['posted'])) {
	$config = array("interface" => $_POST['interface'], "memory" => $_POST['memory']);

	// Save new config
	$handle = fopen($filename, "w+");
        fwrite($handle, "interface=" . $config['interface'] .  "\n");
        fwrite($handle, "memory=" . $config['memory']);
        fclose($handle);
} elseif(file_exists($filename)) {
	// Read config file content
	$fileContent = explode("\n", file_get_contents($filename));
	while(list(, $item) = each($fileContent)) {
		$cfgLine = explode("=", $item);
		$config[$cfgLine[0]] = $cfgLine[1];
	}
}
?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
<title>CrashPlan Administration</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<link rel="icon" type="image/png" href="images/favicon.png" />
<link rel="stylesheet" type="text/css" href="style.css">
</head>
<body>
	<div id="main">
		<div id="top">
			<a href="cgi-bin/backup.cgi"><img src="images/download.gif" />Download configuration and log files</a>
			<div class="topSpace">
				<a href="http://forum.qnap.com/viewforum.php?f=227"><img src="images/forum.gif" />Got a question ? Need help ? Want to thank packager ?</a>
			</div>
		</div>

		<form method="post">
			<div id="bottomLeft">
				<img src="images/<?php if(!isset($config['interface'])) { echo "warning.gif"; } else { echo "success.gif";  } ?>"<?php if(!isset($config['interface'])) { echo " title=\"Listening IP not yet set!\""; } ?> />
				IP CrashPlan will be listening on:
				<select name="interface">
					<?php if($eth0_addr) { ?>
						<option value="eth0"<?php if(isset($config['interface']) && $config['interface']=="eth0") { echo " SELECTED"; }?>><?php echo $eth0_addr; ?></option>
					<?php } ?>
					<?php if($eth1_addr) { ?>
						<option value="eth1"<?php if(isset($config['interface']) && $config['interface']=="eth1") { echo " SELECTED"; }?>><?php echo $eth1_addr; ?></option>
					<?php } ?>
					<?php if($bond0_addr) { ?>
						<option value="bond0"<?php if(isset($config['interface']) && $config['interface']=="bond0") { echo " SELECTED"; }?>><?php echo $bond0_addr; ?></option>
                                	<?php } ?>
					<?php if($wlan0_addr) { ?>
						<option value="wlan0"<?php if(isset($config['interface']) && $config['interface']=="wlan0") { echo " SELECTED"; }?>><?php echo $wlan0_addr; ?></option>
                                	<?php } ?>
				</select>

				<div class="topSpace">
					<img src="images/ram.gif" />
					CrashPlan's Java memory allocation
					<select name="memory">
						<?php
						for($m = $memStep; $m <= $memTotal; $m += $memStep) {
						?>
							<option value="<?php echo ($m); ?>"<?php if(isset($config['memory']) && $config['memory'] == $m) { echo " selected"; } ?>><?php echo ($m) ?> Mb<?php if($m == $memDefault) { echo " (default)"; } ?></option>
						<?php
						}
						?>
					</select>
				</div>
			</div>

			<div id="bottomRight">
				<input type="submit" value="Save" name="posted" />
				<div class="topSpace">Note that you will have to restart the CP service to take it into account!</div>
			</div>
		</form>
	</div>
</body>
</html>
