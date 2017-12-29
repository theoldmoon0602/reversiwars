<?php
$json = [];
$mongo = new \MongoDB\Driver\Manager("mongodb://localhost:27017");
if (isset($_GET["battles"])) {
	$query = new \MongoDB\Driver\Query([]);
	foreach ($mongo->executeQuery("reversi.battle", $query) as $battle) {
		$json []= [
			"id" => $battle->id,
			"user1" => $battle->user1,
			"user2" => $battle->user2,
			"winner" => $battle->winner,
			"black" => $battle->black,
			"white" => $battle->white,
		];
	}
}
else if (isset($_GET["users"])) {
	$query = new \MongoDB\Driver\Query([], ["sort" => ["rating" => -1 ]]);
	foreach ($mongo->executeQuery("reversi.user", $query) as $user) {
		$json []= [
			"username" => $user->username,
			"rating" => $user->rating,
		];
	}
}
else if (isset($_GET["log"]) && isset($_GET["id"]) && isset($_GET["turn"])) {
	$query = new \MongoDB\Driver\Query(["id" => intval($_GET["id"]), "turn" => intval($_GET["turn"])]);
	$log = $mongo->executeQuery("reversi.log", $query)->toArray();
	if (count($log) == 0) {
		$json = ["error" => "invalid request"];
	}
	else {
		$log = $log[0];
		if ($log->action == "pass") {
			$json = [
				"action" => "pass",
				"isGameEnd" => false,
				"board" => $log->board
			];
		}
		else {
			$json = [
				"action" => "put",
				"x" => $log->x,
				"y" => $log->y,
				"isGameEnd" => $log->isGameEnd === "true",
				"board" => $log->board
			];
		}
	}
}
else {
	$json = ["error" => "invalid request"];
}
echo json_encode($json, JSON_UNESCAPED_UNICODE) . PHP_EOL;
