import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/keystone_mark.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    void web(String url) =>
        launchUrlString(url, mode: LaunchMode.externalApplication);

    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('More', style: KeystoneType.body(ks.mu)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: KeystoneMark(width: 56),
            ),
            const SizedBox(height: 12),
            Text('Keystone', style: KeystoneType.title(ks.tx)),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (_, s) => Text(
                s.hasData ? 'Version ${s.data!.version}' : ' ',
                style: KeystoneType.secondary(ks.mu),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '© 2026 Perz3us. Based on luci-mobile by cogwheel0.',
              style: KeystoneType.secondary(ks.mu),
            ),
            const SizedBox(height: 16),
            KsRow(
              title: 'Licences',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Keystone',
              ),
            ),
            KsRow(
              title: 'Original project',
              onTap: () => web(AppConfig.upstreamRepositoryUrl),
            ),
            KsRow(
              title: 'Perz3us on GitHub',
              onTap: () => web(AppConfig.githubRepositoryUrl),
            ),
            KsRow(
              title: 'Sponsor Keystone',
              onTap: () => web(AppConfig.sponsorUrl),
            ),
          ],
        ),
      ),
    );
  }
}
