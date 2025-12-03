import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  final game = GalagaGame();
  runApp(
    GameWidget(
      game: game,
      overlayBuilderMap: {
        'gameover': (_, __) => GameOverOverlay(onRestart: game.resetGame),
      },
    ),
  );
}

class GalagaGame extends FlameGame
    with HasCollisionDetection, HasKeyboardHandlerComponents, TapDetector {
  GalagaGame();

  late final PlayerShip _player;
  late final TextComponent _scoreText;
  late final TextComponent _livesText;
  int _score = 0;
  int _lives = 3;
  int _wave = 1;
  final Timer _enemySpawnTimer = Timer(2, repeat: true);
  final Random _rng = Random();

  @override
  Color backgroundColor() => const Color(0xFF000010);

  @override
  Future<void> onLoad() async {
    camera.viewport = FixedResolutionViewport(Vector2(480, 640));
    await super.onLoad();

    _player = PlayerShip(position: Vector2(size.x / 2, size.y - 80));
    await add(_player);

    await add(Starfield());

    _scoreText = TextComponent(
      text: 'SCORE 00000',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 16,
          letterSpacing: 2,
        ),
      ),
      anchor: Anchor.topLeft,
      position: Vector2(12, 12),
      priority: 10,
    );

    _livesText = _scoreText.clone()
      ..text = 'LIVES 3'
      ..position = Vector2(size.x - 120, 12);

    await add(_scoreText);
    await add(_livesText);

    _enemySpawnTimer.onTick = _spawnWave;
    _enemySpawnTimer.start();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _enemySpawnTimer.update(dt);
  }

  void _spawnWave() {
    final double spacing = size.x / (_wave + 2);
    for (int i = 0; i < _wave + 2; i++) {
      final x = spacing / 2 + spacing * i;
      add(EnemyFighter(
        startX: x,
        speed: 40 + _wave * 6,
        amplitude: 20 + 6 * _wave,
        phase: _rng.nextDouble() * pi,
      ));
    }
    _wave = (_wave % 4) + 1;
  }

  void registerHit(EnemyFighter enemy) {
    _score += 50;
    _scoreText.text = 'SCORE ${_score.toString().padLeft(5, '0')}';

    if (_score % 500 == 0) {
      _lives = min(5, _lives + 1);
      _livesText.text = 'LIVES $_lives';
    }

    add(Explosion(position: enemy.position.clone()));
  }

  void playerHit() {
    if (_lives <= 0) {
      return;
    }

    _lives -= 1;
    _livesText.text = 'LIVES $_lives';
    add(Explosion(position: _player.position.clone()));

    if (_lives == 0) {
      overlays.add('gameover');
      pauseEngine();
    } else {
      _player.respawn(position: Vector2(size.x / 2, size.y - 80));
    }
  }

  void resetGame() {
    overlays.remove('gameover');
    _score = 0;
    _wave = 1;
    _lives = 3;
    _scoreText.text = 'SCORE 00000';
    _livesText.text = 'LIVES 3';
    children.whereType<EnemyFighter>().forEach((enemy) => enemy.removeFromParent());
    children.whereType<EnemyBullet>().forEach((bullet) => bullet.removeFromParent());
    children.whereType<PlayerBullet>().forEach((bullet) => bullet.removeFromParent());
    _player.respawn(position: Vector2(size.x / 2, size.y - 80));
    resumeEngine();
  }

  @override
  KeyEventResult onKeyEvent(RawKeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    final isDown = event is RawKeyDownEvent;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _player.moveLeft = isDown;
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.keyD) {
      _player.moveRight = isDown;
      return KeyEventResult.handled;
    }
    if (isDown &&
        (event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.arrowUp)) {
      _player.fire();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void onTapDown(TapDownInfo info) {
    _player.fire();
  }
}

class PlayerShip extends PositionComponent with HasGameRef<GalagaGame>, CollisionCallbacks {
  PlayerShip({required Vector2 position}) {
    size = Vector2(44, 36);
    anchor = Anchor.center;
    this.position = position;
    add(RectangleHitbox());
  }

  bool moveLeft = false;
  bool moveRight = false;
  double _cooldown = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    priority = 5;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final bodyPaint = Paint()..color = Colors.white;
    final accentPaint = Paint()..color = const Color(0xFF7CFC00);

    final hull = Path()
      ..moveTo(size.x / 2, 0)
      ..lineTo(size.x, size.y * 0.8)
      ..lineTo(size.x * 0.65, size.y)
      ..lineTo(size.x * 0.35, size.y)
      ..lineTo(0, size.y * 0.8)
      ..close();
    canvas.drawPath(hull, bodyPaint);
    canvas.drawRect(Rect.fromLTWH(size.x * 0.45, size.y * 0.4, size.x * 0.1, size.y * 0.4), accentPaint);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _cooldown = max(0, _cooldown - dt);

    double direction = 0;
    if (moveLeft) direction -= 1;
    if (moveRight) direction += 1;
    position.x += direction * 180 * dt;
    position.x = position.x.clamp(size.x / 2, gameRef.size.x - size.x / 2);
  }

  void fire() {
    if (_cooldown > 0) return;
    _cooldown = 0.25;
    gameRef.add(PlayerBullet(position: position.clone() + Vector2(0, -size.y / 2)));
  }

  void respawn({required Vector2 position}) {
    this.position = position;
    moveLeft = false;
    moveRight = false;
    _cooldown = 0;
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyFighter || other is EnemyBullet) {
      gameRef.playerHit();
    }
  }
}

class PlayerBullet extends RectangleComponent with CollisionCallbacks, HasGameRef<GalagaGame> {
  PlayerBullet({required Vector2 position})
      : super(position: position, size: Vector2(4, 14), anchor: Anchor.center, paint: Paint()..color = Colors.cyan);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y -= 400 * dt;
    if (position.y < -20) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyFighter) {
      other.destroyedByPlayer();
      removeFromParent();
    }
  }
}

class EnemyFighter extends PositionComponent with CollisionCallbacks, HasGameRef<GalagaGame> {
  EnemyFighter({required this.startX, required this.speed, required this.amplitude, required this.phase}) {
    size = Vector2(36, 28);
    anchor = Anchor.center;
    position = Vector2(startX, -size.y);
    add(RectangleHitbox());
  }

  final double startX;
  final double speed;
  final double amplitude;
  final double phase;
  double _time = 0;
  double _shotTimer = 1.2;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    _shotTimer -= dt;

    final sway = sin(_time * 2 + phase) * amplitude;
    position
      ..y += speed * dt
      ..x = startX + sway;

    if (_shotTimer < 0 && position.y > 0) {
      _shotTimer = 2.4 + gameRef.random.nextDouble();
      gameRef.add(EnemyBullet(position: position.clone() + Vector2(0, size.y / 2)));
    }

    if (position.y > gameRef.size.y + size.y) {
      removeFromParent();
      gameRef.playerHit();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final body = Paint()..color = const Color(0xFFFFE66D);
    final cockpit = Paint()..color = const Color(0xFFAA00FF);

    final hull = Path()
      ..moveTo(size.x / 2, 0)
      ..lineTo(size.x, size.y * 0.6)
      ..lineTo(size.x * 0.8, size.y)
      ..lineTo(size.x * 0.2, size.y)
      ..lineTo(0, size.y * 0.6)
      ..close();
    canvas.drawPath(hull, body);
    canvas.drawRect(Rect.fromLTWH(size.x * 0.4, size.y * 0.4, size.x * 0.2, size.y * 0.3), cockpit);
  }

  void destroyedByPlayer() {
    gameRef.registerHit(this);
    removeFromParent();
  }
}

class EnemyBullet extends RectangleComponent with CollisionCallbacks, HasGameRef<GalagaGame> {
  EnemyBullet({required Vector2 position})
      : super(position: position, size: Vector2(5, 16), anchor: Anchor.center, paint: Paint()..color = const Color(0xFFFF4444));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y += 260 * dt;
    if (position.y > gameRef.size.y + 20) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      removeFromParent();
    }
  }
}

class Starfield extends Component with HasGameRef<GalagaGame> {
  Starfield();

  late final Timer _spawnTimer;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _spawnTimer = Timer(0.05, repeat: true, onTick: () => _spawnParticle());
  }

  @override
  void update(double dt) {
    super.update(dt);
    _spawnTimer.update(dt);
  }

  void _spawnParticle() {
    final startX = gameRef.size.x * gameRef.random.nextDouble();
    final speed = 60 + gameRef.random.nextDouble() * 120;
    gameRef.add(Star(position: Vector2(startX, -2), speed: speed));
  }
}

class Star extends CircleComponent with HasGameRef<GalagaGame> {
  Star({required Vector2 position, required this.speed})
      : super(
          position: position,
          radius: 1.5,
          paint: Paint()
            ..color = Colors.white.withOpacity(0.85)
            ..style = PaintingStyle.fill,
        );

  final double speed;

  @override
  void update(double dt) {
    super.update(dt);
    position.y += speed * dt;
    if (position.y > gameRef.size.y + 2) {
      removeFromParent();
    }
  }
}

class Explosion extends PositionComponent with HasPaint {
  Explosion({required Vector2 position}) {
    this.position = position;
    size = Vector2.all(32);
    anchor = Anchor.center;
    paint = Paint()..color = Colors.orangeAccent;
  }

  double _life = 0.4;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x / 2, paint);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life -= dt;
    paint.color = paint.color.withOpacity(max(0, _life * 2.5));
    if (_life <= 0) {
      removeFromParent();
    }
  }
}

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({super.key, required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 10),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'GAME OVER',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.redAccent,
                          fontFamily: 'monospace',
                          letterSpacing: 4,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Press SPACE or tap to fire. Use arrow keys (or A/D) to slide.',
                    style: TextStyle(color: Colors.white70, fontFamily: 'monospace'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onRestart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade400,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('INSERT COIN'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
