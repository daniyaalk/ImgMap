import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bump to show the disclaimer again to everyone, e.g. after changing it.
const disclaimerVersion = 1;

const contactEmail = 'me@daniyaalkhan.com';
final _appRepo = Uri.parse('https://github.com/daniyaalk/ImgMap');
final _backendRepo = Uri.parse('https://github.com/daniyaalk/imgmap-backend');

/// Shown before the app can be used, until accepted; [onAccept] is called
/// when the user confirms.
class DisclaimerScreen extends StatefulWidget {
  const DisclaimerScreen({super.key, required this.onAccept});

  final VoidCallback onAccept;

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'Before you start',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                const DisclaimerText(),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _understood,
                  onChanged: (v) => setState(() => _understood = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I understand this app must not be used for navigation.',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _understood ? widget.onAccept : null,
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The disclaimer itself, with working links.
class DisclaimerText extends StatelessWidget {
  const DisclaimerText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge;
    final link = body?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    TextSpan linkTo(String text, Uri uri) => TextSpan(
      text: text,
      style: link,
      recognizer: TapGestureRecognizer()
        ..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication),
    );

    Widget point(int n, String title, List<InlineSpan> text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 13, child: Text('$n')),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: body,
                children: [
                  TextSpan(
                    text: '$title ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ...text,
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        point(1, 'Never use this for actual navigation.', const [
          TextSpan(
            text:
                'ImgMap is for hobbyists and aviation enthusiasts only. Always '
                'use official, current charts and certified equipment.',
          ),
        ]),
        point(2, 'The information may be wrong.', const [
          TextSpan(
            text:
                'Charts are placed on the map by an automated data pipeline '
                'built with the help of AI, and may contain errors. There is '
                'no guarantee that anything shown is correct.',
          ),
        ]),
        point(3, 'No guarantee of accuracy, but suggestions are welcome.', [
          const TextSpan(text: 'Email '),
          linkTo(
            contactEmail,
            Uri(
              scheme: 'mailto',
              path: contactEmail,
              queryParameters: {'subject': 'ImgMap'},
            ),
          ),
          const TextSpan(
            text: '. Even better, raise a pull request with your change: ',
          ),
          linkTo('the app', _appRepo),
          const TextSpan(text: ' or '),
          linkTo('the chart pipeline', _backendRepo),
          const TextSpan(text: '.'),
        ]),
      ],
    );
  }
}

/// The disclaimer again, any time, from the home screen.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About & disclaimer')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: const [DisclaimerText()],
    ),
  );
}
