import 'package:flutter/material.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/services/gemini_tts_service.dart';
import 'package:provider/provider.dart';

class LanguageSelectorButton extends StatelessWidget {
  final bool compact;
  final Color? backgroundColor;
  final Color? textColor;

  const LanguageSelectorButton({
    super.key,
    this.compact = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCode = localeProvider.languageCode;
    final currentName =
        LocaleProvider.supportedLanguages[currentCode] ?? 'English';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showLanguageModal(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: backgroundColor ??
                (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.language_rounded,
                size: compact ? 16 : 18,
                color: textColor ??
                    (isDark ? AppTheme.darkTextLight : AppTheme.primaryOrange),
              ),
              const SizedBox(width: 6),
              Text(
                compact ? currentCode.toUpperCase() : currentName,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: textColor ??
                      (isDark ? AppTheme.darkTextLight : AppTheme.textDark),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: compact ? 16 : 18,
                color: textColor ??
                    (isDark ? AppTheme.darkTextDim : AppTheme.textGray),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final locProvider = Provider.of<LocaleProvider>(ctx);
        final activeCode = locProvider.languageCode;

        return Container(
          padding: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161F2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryOrange.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.translate_rounded,
                          color: AppTheme.primaryOrange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose App Language',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            'Select your preferred regional language',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextDim
                                  : AppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    children: LocaleProvider.supportedLanguages.entries.map((e) {
                      final isSelected = e.key == activeCode;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 2),
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryOrange
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.grey.shade100),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            e.key.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark
                                      ? AppTheme.darkTextLight
                                      : AppTheme.textDark),
                            ),
                          ),
                        ),
                        title: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? AppTheme.primaryOrange
                                : (isDark
                                    ? AppTheme.darkTextLight
                                    : AppTheme.textDark),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.primaryOrange,
                                size: 22,
                              )
                            : null,
                        onTap: () {
                          locProvider.setLanguage(e.key);
                          GeminiTTSService.setLanguage(e.key);
                          Navigator.of(ctx).pop();
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

