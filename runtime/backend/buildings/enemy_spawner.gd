extends Building
class_name EnemySpawner

var spawn_timer: float = 0

func tick(in_delta: float):
	super.tick(in_delta)
	spawn_timer += in_delta
	while spawn_timer >= 1:
		spawn_timer -= 1
		var enemy: Entity = Entity.create("slime")
		enemy.position = Vector2(axis.x, axis.y)
		Level.current.room.add_entity(enemy)
		enemy.tick(spawn_timer)
