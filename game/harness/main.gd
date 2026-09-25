extends Node
## Entry point. Structural only: hands control to the Harness autoload.
##
## Everything this project shows on screen is built by code from res://world and
## res://config, so this scene stays empty by design.


func _ready() -> void:
    Harness.begin(self)
