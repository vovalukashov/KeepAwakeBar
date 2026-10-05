# KeepAwakeBar

<img src="Design/OwlAppIcon.png" width="128" alt="KeepAwakeBar owl icon">

[Скачать приложение / Download](https://github.com/vovalukashov/KeepAwakeBar/releases)

**Тестовая сборка:** текущий релиз имеет локальную ad-hoc подпись, без Developer ID и нотарификации Apple. macOS может блокировать первый запуск; корпоративные политики могут запрещать установку. Подробнее: [установка](INSTALL.txt) и [проверка релиза](VERIFICATION.md).

Нативная macOS menu bar утилита на Swift/SwiftUI, macOS 13+. Два независимых режима, без окна и иконки в Dock (`LSUIElement = true`). Зависимостей у приложения нет.

## Сборка в Xcode

1. Откройте `KeepAwakeBar.xcodeproj` (не `Package.swift`: это отдельный пакет тестов).
2. Выберите схему **KeepAwakeBar**, устройство **My Mac**.
3. В Signing & Capabilities оставьте **Sign to Run Locally** либо выберите свою Development Team. При необходимости задайте собственный Bundle Identifier.
4. Нажмите **⌘R**. В menu bar появится монохромная сова с глазами-кнопками питания. Оба режима выключены — глаза закрыты; Caffeinate включён — глаза открыты; Disable Sleep включён — глаза огромные (приоритет над Caffeinate). Пока системное состояние неизвестно, сова с открытыми глазами; подсказка сообщает о проверке состояния. Оригинал SVG сохранён в `Design/OriginalIcon.svg`; для menu bar используется растровая template-версия совы с прозрачностью в масштабах 1×/2×/3×, а для Finder — объёмная сова с янтарными глазами, исходник `Design/OwlAppIcon.png`.
5. Для установки: Product → Show Build Folder in Finder → Products → Debug/Release; скопируйте `KeepAwakeBar.app` в Applications.

Готовый `.xcodeproj` включён: XcodeGen для сборки не нужен. `project.yml` — исходное описание проекта, если захотите его перегенерировать (`xcodegen generate`). App Sandbox намеренно отключён: этот MVP запускает административную команду через AppleScript. Hardened Runtime включён. Для распространения за пределами своего Mac нужны Developer ID signing и notarization; локальная сборка их не заменяет.

Сборка из терминала (из каталога проекта):

```sh
xcodebuild -project KeepAwakeBar.xcodeproj -scheme KeepAwakeBar \
  -configuration Release -derivedDataPath /tmp/KeepAwakeBar-build \
  CODE_SIGN_IDENTITY=- build
```

Приложение: `/tmp/KeepAwakeBar-build/Build/Products/Release/KeepAwakeBar.app`.

## Меню и права администратора

Меню содержит только **Caffeinate**, **Disable Sleep** и **Quit**. Галочка означает, что режим включён. Дополнительных строк allowed/disabled нет. Ошибки показываются отдельным диалогом. Disable Sleep недоступен до завершения авторизации или если фактическое состояние неизвестно.

При запуске macOS один раз запрашивает права администратора через AppleScript `do shell script … with administrator privileges`. Пароль приложение не получает и не сохраняет; macOS может временно кешировать разрешение. Запускается только небольшой `KeepAwakeBarHelper`, само приложение продолжает работать с обычными правами. Caffeinate работает независимо от авторизации. Отмена запроса оставляет Caffeinate доступным; чтобы повторить авторизацию, перезапустите приложение.

Помощник принимает по локальному Unix-сокету только проверку связи и две операции: `/usr/bin/pmset -a disablesleep 1` либо `0`. Произвольные команды и аргументы не принимаются. Проверяются kernel-provided UID/PID клиента и время рождения процесса; клиент проверяет root UID сервера. Сокет имеет случайное имя и принадлежит root в sticky `/private/tmp`. Помощник отслеживает выход конкретного процесса через kqueue и завершается вместе с ним. Если приложение не подключилось, помощник завершится через 60 секунд. Постоянный daemon, sudoers и сохранение пароля не используются.

Реализация: `Helper/main.c` и `Core/SessionSleepAuthorizer.swift`. Старый `AppleScriptSleepAuthorizer` сохранён как отдельный адаптер, но UI его больше не использует. Для будущего подписанного production-приложения этот адаптер можно заменить на SMAppService/XPC; локальная сборка не устанавливает постоянный privileged helper.

При запуске, открытии меню и каждые 15 секунд читается `pmset -g`. Если ключ отсутствует, читается фактическое свойство `SleepDisabled` у `IOPMrootDomain`. После изменения выполняется повторная проверка.

**Quit не сбрасывает Disable Sleep.** Это глобальная настройка. Отключите её, когда она не нужна; не убирайте работающий Mac в сумку. Восстановление вручную:

```sh
sudo /usr/bin/pmset -a disablesleep 0
```

## Caffeinate

По умолчанию приложение запускает отдельный `/usr/bin/caffeinate -d -i -m -s -u -w <PID приложения>`.

- `-d`: не усыплять дисплей.
- `-i`: не усыплять систему из-за бездействия.
- `-m`: не усыплять диск из-за бездействия; актуальность зависит от накопителя.
- `-s`: предотвращать системный сон **при питании от сети**.
- `-u`: заявить активность пользователя, при необходимости включить дисплей. Без `-t` это утверждение действует **5 секунд**, а не всё время работы процесса.
- `-w`: завершить Caffeinate после завершения процесса приложения, в том числе аварийного.

Флаги задаются в `Core/CaffeinateOptions.swift`; меню намеренно содержит только два переключателя. Сохранённые ранее настройки используются при запуске.

Caffeinate не заменяет системный `disablesleep` и не обещает работу с закрытой крышкой. При обычном старте приложения он выключен. Для обновления уже запущенной копии есть одноразовый аргумент `--resume-caffeinate`: он запускает собственный Caffeinate с сохранёнными флагами. Это не настройка автозапуска и не влияет на следующие обычные запуски. Приложение отслеживает только свой объект `Process`, показывает PID, замечает неожиданное завершение. Чужие процессы не ищет и не останавливает. Quit посылает SIGTERM только своему дочернему процессу; `-w` дополнительно ограничивает срок его жизни.

Во время системной авторизации Quit недоступен: иначе ещё открытый запрос мог бы изменить настройку уже после выхода приложения.

## Структура

```text
KeepAwakeBar.xcodeproj/          Готовый Xcode-проект и общая схема
KeepAwakeBar/
  KeepAwakeBarApp.swift          MenuBarExtra, меню, завершение приложения
  AppModel.swift                 Состояние UI, обновление, UserDefaults
  Info.plist                    LSUIElement и метаданные
  Core/
    CommandRunner.swift         Асинхронный запуск системных команд
    SystemSleepService.swift    Чтение состояния и адаптер авторизации
    CaffeinateController.swift  Собственный процесс и его жизненный цикл
    CaffeinateOptions.swift     Типизированные флаги
Tests/KeepAwakeCoreTests/       Проверки логики и процессов
Package.swift                  Swift Package только для тестирования Core
project.yml                    Необязательный исходник XcodeGen
```

## Проверка

```sh
swift test --package-path . --scratch-path /tmp/KeepAwakeBar-tests
```

Тесты проверяют разбор `pmset`, неопределённое состояние, фиксированные команды авторизации, флаги, обработку кодов возврата, реальное чтение состояния, запуск/остановку собственного Caffeinate и сохранность отдельного процесса. Для короткой проверки процессов используется только `-i`; системные настройки тесты не меняют.

Ручная проверка административного сценария:

1. При старте подтвердите системный запрос администратора. Затем несколько раз переключите Disable Sleep: новых запросов быть не должно.
2. Сверьте состояние с `pmset -g`; если ключ отсутствует — `ioreg -r -d 1 -c IOPMrootDomain` и его `SleepDisabled`.
3. После переключения Disable Sleep проверьте `pmset -g` и верните исходное состояние.
4. Включите Caffeinate, проверьте PID и `pmset -g assertions`. Отключите: завершится именно этот процесс.
5. Проверьте оба режима одновременно и выход из приложения. Системный флаг сохраняется, собственный Caffeinate завершается.

Интерактивный ввод пароля и физическое закрытие крышки требуют проверки владельцем Mac. Автоматические тесты не подтверждают эти сценарии.

## Источники

- [Apple: MenuBarExtra и LSUIElement](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple: Calling Command-Line Tools](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/CallCommandLineUtilities.html)
- [Apple: AppleScript Commands Reference](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_cmds.html)
- Локальные `man caffeinate`, `man pmset` и IOKit headers установленного SDK.
