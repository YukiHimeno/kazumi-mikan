import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/utils/constants.dart';

void main() {
  test('About links and Bangumi user agent identify the fork', () {
    expect(ApiEndpoints.sourceUrl,
        'https://github.com/YukiHimeno/kazumi-mikan');
    expect(ApiEndpoints.projectUrl, ApiEndpoints.sourceUrl);
    expect('${ApiEndpoints.sourceUrl}/issues',
        'https://github.com/YukiHimeno/kazumi-mikan/issues');
    expect(ApiEndpoints.upstreamUrl, 'https://github.com/Predidit/Kazumi');
    expect(bangumiHTTPHeader['user-agent'],
        contains('YukiHimeno/Kazumi-Mikan/'));
    expect(bangumiHTTPHeader['user-agent'], contains(ApiEndpoints.sourceUrl));
  });
}
