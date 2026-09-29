import 'package:flutter/material.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';

/// Тестовый экран B0: Финни и питомцы анимируются, здания в целом масштабе.
/// Открывается из демо-панели; ребёнку не показывается.
class SpriteTestScreen extends StatelessWidget {
  const SpriteTestScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Арт: проверка')),
        body: FutureBuilder<AssetRegistry>(
          future: AssetRegistry.load(),
          builder: (BuildContext context, AsyncSnapshot<AssetRegistry> s) {
            final AssetRegistry? reg = s.data;
            if (reg == null) return const SizedBox.shrink();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _Row(<Widget>[
                  for (final String species in reg.ids('finni'))
                    if (reg.finni(species) case final SpriteRef f)
                      SpriteAnim(
                          key: ValueKey<String>('finni:$species'),
                          sprite: f,
                          tag: 'idle-1',
                          height: 120,
                          semanticLabel: species),
                ]),
                if (reg.finni('finni-a1') case final SpriteRef f)
                  _Row(<Widget>[
                    SpriteAnim(sprite: f, tag: 'walk', height: 120),
                  ]),
                _Row(<Widget>[
                  for (final String id in reg.ids('pets'))
                    if (reg.pet(id) case final SpriteRef p)
                      Column(children: <Widget>[
                        SpriteAnim(
                            key: ValueKey<String>('pet:$id:sleep'),
                            sprite: p,
                            tag: 'sleep',
                            scale: 2,
                            semanticLabel: id),
                        SpriteAnim(sprite: p, tag: 'wake', scale: 2),
                      ]),
                ]),
                _Row(<Widget>[
                  for (final String id in reg.ids('buildings'))
                    PixelImage(reg.building(id), scale: 1, semanticLabel: id),
                ]),
                PixelImage(reg.room()),
              ],
            );
          },
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: children,
        ),
      );
}
