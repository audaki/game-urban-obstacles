extends Control

onready var high_score_label:Label = $HighScore
var high_score = 0

func _on_GameScreen_game_finished(score):
	visible = true
	high_score = max(high_score, score)
	high_score_label.visible = true
	high_score_label.text = "High Score %s" % high_score


func _on_GameScreen_game_started():
	visible = false
