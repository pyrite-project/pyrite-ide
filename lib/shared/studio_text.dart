import 'package:flutter/material.dart';

class UseText extends StatelessWidget {
  const UseText(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        color: color ?? Theme.of(context).colorScheme.onSurface,
        fontFamily: "HarmonyOS Sans SC",
      ),
    );
  }
}

class TextDisplayLarge extends StatelessWidget {
  const TextDisplayLarge(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.displayLarge!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextDisplayMedium extends StatelessWidget {
  const TextDisplayMedium(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.displayMedium!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextTitleLarge extends StatelessWidget {
  const TextTitleLarge(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.titleLarge!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextTitleMedium extends StatelessWidget {
  const TextTitleMedium(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.titleMedium!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextTitleSmall extends StatelessWidget {
  const TextTitleSmall(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.titleSmall!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextBodyLarge extends StatelessWidget {
  const TextBodyLarge(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.bodyLarge!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextBodyMedium extends StatelessWidget {
  const TextBodyMedium(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextBodySmall extends StatelessWidget {
  const TextBodySmall(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.bodySmall!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextHeadlineMedium extends StatelessWidget {
  const TextHeadlineMedium(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = Theme.of(context).textTheme.headlineMedium!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFamily: "HarmonyOS Sans SC",
    );
    return Text(data, style: style);
  }
}

class TextLogo extends StatelessWidget {
  const TextLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: "Pyrite",
        style: Theme.of(context).textTheme.headlineMedium!.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
        children: [
          TextSpan(
            text: "IDE",
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}

class AppBarTextLogo extends StatelessWidget {
  const AppBarTextLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: "Pyrite",
        style: Theme.of(context).textTheme.headlineSmall!.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
        children: [
          TextSpan(
            text: "IDE",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}
