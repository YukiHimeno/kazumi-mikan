import 'package:flutter/material.dart';

import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/pages/about/about_widgets.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('关于'),
        body: AboutContent(
          children: [
            const _ProjectHeader(),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final sections = [
                ContentSection.group(
                  title: '项目',
                  children: const [
                    AboutLinkTile(
                      icon: Icons.code_rounded,
                      title: '源代码',
                      url: ApiEndpoints.sourceUrl,
                    ),
                    AboutLinkTile(
                      icon: Icons.language_rounded,
                      title: '项目主页',
                      url: ApiEndpoints.projectUrl,
                    ),
                    AboutLinkTile(
                      icon: Icons.bug_report_rounded,
                      title: '问题反馈',
                      url: '${ApiEndpoints.sourceUrl}/issues',
                    ),
                  ],
                ),
                ContentSection.group(
                  title: '开源',
                  children: [
                    const AboutLinkTile.route(
                      icon: Icons.favorite_outline_rounded,
                      title: '致谢',
                      route: '/settings/about/credits',
                    ),
                    const AboutLinkTile(
                      icon: Icons.balance_rounded,
                      title: 'GPL-3.0 许可证（本项目）',
                      url: '${ApiEndpoints.sourceUrl}/blob/main/LICENSE',
                    ),
                    const AboutLinkTile(
                      icon: Icons.source_outlined,
                      title: '原版 Kazumi · Predidit（上游）',
                      url: ApiEndpoints.upstreamUrl,
                    ),
                    const AboutLinkTile.route(
                      icon: Icons.description_outlined,
                      title: '第三方许可证',
                      route: '/settings/about/license',
                    ),
                  ],
                ),
              ];
              if (constraints.maxWidth >= 640 &&
                  MediaQuery.textScalerOf(context).scale(14) < 21) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sections[0]),
                    const SizedBox(width: 16),
                    Expanded(child: sections[1]),
                  ],
                );
              }
              return Column(
                children: [
                  sections[0],
                  const SizedBox(height: 24),
                  sections[1]
                ],
              );
            }),
          ],
        ),
      );
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Kazumi Mikan',
              style: theme.textTheme.displayMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ApiEndpoints.version,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '从蜜柑计划查找 BT 资源，在播放器中边下边播的开源番剧应用',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            '本 fork 暂无独立版本发布；Android 应用内更新已停用，请以项目仓库为准。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
