import 'package:finlit/features/world/home/room_skins.dart';
import 'package:flutter_test/flutter_test.dart';

// Ловит (Денис 29.09): варианты одного предмета — его вид, а не новые
// тумбочки. В комнате один вид на предмет: последний купленный, а «выбрать»
// из купленных его меняет; не купленный выбрать нельзя.
void main() {
  test('один вид на предмет: последний купленный или выбранный из купленных',
      () {
    const List<String> owned = <String>[
      'poster_city',
      'skin_cabinet__19a',
      'skin_bed__4a',
      'skin_cabinet__20b',
    ];
    expect(equippedSkins(owned, const <String, String>{}), <String, String>{
      'skin_cabinet': 'skin_cabinet__20b',
      'skin_bed': 'skin_bed__4a',
    });
    expect(
        equippedSkins(owned, const <String, String>{
          'skin_cabinet': 'skin_cabinet__19a',
          'skin_bed': 'skin_bed__5a',
        }),
        <String, String>{
          'skin_cabinet': 'skin_cabinet__19a',
          'skin_bed': 'skin_bed__4a',
        });
    expect(
        furnitureSkins(equippedSkins(owned, const <String, String>{})),
        <String, String>{
          'bedside_cabinet': 'skin_cabinet__20b',
          'bed': 'skin_bed__4a',
        });
    expect(skinFamily('skin_cabinet__20b'), 'skin_cabinet__20');
    expect(skinFamily('poster_city'), 'poster_city');
  });
}
