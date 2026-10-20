# Docky unsigned preview

This preview is built from the `Mark1708/docky` repository for evaluation before the fork has a Developer ID Application certificate. It is ad-hoc signed and is not notarized by Apple.

## Install

1. Quit any running Docky instance.
2. Open the DMG and drag `Docky.app` to `Applications`.
3. Try to open Docky once.
4. If macOS blocks it, open **System Settings → Privacy & Security**, find the Docky security message, and click **Open Anyway**.
5. Confirm the prompt with your macOS password.
6. Grant Accessibility, Screen Recording, and any optional permissions required by the features you use.

Do not disable Gatekeeper globally. The Terminal command that removes quarantine is intentionally not the primary installation path.

## Verify the download

From the directory containing the downloaded files:

```sh
shasum -a 256 -c SHA256SUMS
gh attestation verify Docky-*.dmg --repo Mark1708/docky
```

Both commands must succeed before installation. The GitHub attestation proves which repository and workflow produced the DMG; it does not make the application trusted by Apple Gatekeeper.

## Limitations

- The application is not signed with Developer ID and is not notarized.
- Automatic updates are disabled. Install each preview manually.
- Replacing an ad-hoc signed build can cause macOS to request Accessibility or Screen Recording permission again.
- This preview is not the stable `v0.10.0` release.

## Русская инструкция

Это предварительная сборка без сертификата Developer ID Application и без нотарификации Apple.

1. Завершите работающий Docky.
2. Откройте DMG и перетащите `Docky.app` в `Applications`.
3. Попробуйте запустить Docky один раз.
4. Если macOS заблокирует запуск, откройте **Системные настройки → Конфиденциальность и безопасность**, найдите сообщение о Docky и нажмите **Всё равно открыть**.
5. Подтвердите действие паролем macOS.
6. Повторно выдайте Accessibility, Screen Recording и другие используемые разрешения, если macOS их запросит.

Не отключайте Gatekeeper глобально. Автоматические обновления в preview-сборке отключены; следующие preview устанавливаются вручную.
