// Юніт-тести логіки, що не залежить від плагінів.
import 'package:flutter_test/flutter_test.dart';

import 'package:vps_admin/models.dart';
import 'package:vps_admin/services/ai_service.dart';

void main() {
  test('ServerProfile серіалізується туди-назад', () {
    final p = ServerProfile(
      name: 'Test',
      host: '1.2.3.4',
      port: 2222,
      username: 'ubuntu',
      auth: AuthType.key,
      defaultDir: '/srv',
    );
    final back = ServerProfile.fromJson(p.toJson());
    expect(back.id, p.id);
    expect(back.host, '1.2.3.4');
    expect(back.port, 2222);
    expect(back.auth, AuthType.key);
    expect(back.defaultDir, '/srv');
  });

  test('extractCommands витягує bash-блоки', () {
    const md = 'Ось команда:\n```bash\nuptime\n```\nі ще\n```\ndf -h\n```';
    final cmds = extractCommands(md);
    expect(cmds, ['uptime', 'df -h']);
  });
}
