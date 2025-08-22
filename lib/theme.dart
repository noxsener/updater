import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


class CodenfastTheme {
  // Color backGroundColor1 = const Color(0xFF6A1B9A);
  // Color backGroundColor2 = const Color(0xFFC10685);
  // Color backGroundColor3 = const Color(0xFFF44169);
  // Color backGroundColor4 = const Color(0xFFFF8051);
  Color backGroundColor1 = const Color(0xFF222222);
  Color backGroundColor2 = const Color(0xFF212121);
  Color backGroundColor3 = const Color(0xFF121212);
  Color backGroundColor4 = const Color(0xFF111111);

  int animationDuration = 1000;

  MaterialColor blackTransparent = const MaterialColor(
    0x05000000,
    <int, Color>{
      50: Color(0x05000000),
      100: Color(0x10000000),
      200: Color(0x20000000),
      300: Color(0x30000000),
      400: Color(0x40000000),
      500: Color(0x50000000),
      600: Color(0x60000000),
      700: Color(0x70000000),
      800: Color(0x80000000),
      900: Color(0x90000000),
      1000: Color(0xA0000000),
      1100: Color(0xB0000000),
      1200: Color(0xC0000000),
      1300: Color(0xD0000000),
      1400: Color(0xE0000000),
    },
  );

  List<Color> colorList = [
    Color(0xFFc62828), //0
    Color(0xFF6a1b9a), //1
    Color(0xFF4527a0), //2
    Color(0xFF1565c0), //3
    Color(0xFF0277bd), //4
    Color(0xFF00695c), //5
    Color(0xFF2e7d32), //6
    Color(0xFF9e9d24), //7
    Color(0xFFf9a825), //8
    Color(0xFFef6c00), //9
    Color(0xFFd84315), //10
    Color(0xFF4e342e), //11
    Color(0xFF37474f), //12
    Color(0xFFad1457), //13
    Color(0xFF283593), //14
    Color(0xFF00838f), //15
    Color(0xFF558b2f), //16
    Color(0xFFff8f00), //17
    Color(0xFF4e342e) //18
  ];

  MaterialColor cyanTransparent = const MaterialColor(
    0xAA00BCD4,
    <int, Color>{
      50: Color(0x0500BCD4),
      100: Color(0x2200BCD4),
      200: Color(0x4400BCD4),
      300: Color(0x6600BCD4),
      400: Color(0x8800BCD4),
      500: Color(0xAA00BCD4),
      600: Color(0xBB00BCD4),
      700: Color(0xDD00BCD4),
      800: Color(0xEE00BCD4),
      900: Color(0xFF00BCD4),
    },
  );
  static const int _cyanPrimaryValue = 0xFF00BCD4;

  Widget getBody(Widget child) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              backGroundColor1,
              backGroundColor2,
              backGroundColor3,
              backGroundColor4
            ]),
      ),
      padding: const EdgeInsets.all(10),
      child: child,
    );
  }

  ColorScheme colorScheme() {
    return ColorScheme.light(
      primary: colorList[13],
      surface: cyanTransparent,
      secondary: Colors.green,
    );
  }

  TextTheme textTheme() {
    return TextTheme(
      displayLarge: GoogleFonts.museoModerno(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
              shadows: [])),
      displayMedium: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.bold,
              shadows: [])),
      displaySmall: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              shadows: [])),
      headlineLarge: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              shadows: [])),
      headlineMedium: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.bold,
              shadows: [])),
      headlineSmall: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [])),
      titleLarge: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [])),
      titleMedium: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              shadows: [])),
      titleSmall: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              shadows: [])),
      labelLarge: GoogleFonts.roboto(
          textStyle: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18, shadows: [])),
      labelMedium: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              shadows: [])),
      labelSmall: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              shadows: [])),
      bodyLarge: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white, fontSize: 18, shadows: [
          ])),
      bodyMedium: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white, fontSize: 16, shadows: [
          ])),
      bodySmall: GoogleFonts.roboto(
          textStyle: const TextStyle(
              color: Colors.white, fontSize: 14, shadows: [
          ])),
    );
  }

  TextStyle inputFieldStyle() {
    return GoogleFonts.roboto(
        textStyle: const TextStyle(color: Colors.white, fontSize: 16, shadows: [
        ]));
  }

  /*
  TextTheme textTheme2 = TextTheme(
    displayLarge: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 26,
            fontWeight: FontWeight.bold)),
    displayMedium: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold)),
    displaySmall: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.bold)),
    headlineLarge: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold)),
    headlineMedium: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.bold)),
    headlineSmall: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold)),
    titleLarge: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold)),
    titleMedium: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold)),
    titleSmall: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold)),
    labelLarge: GoogleFonts.roboto(
        textStyle: const TextStyle(color: Colors.black, fontSize: 16)),
    labelMedium: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold)),
    labelSmall: GoogleFonts.roboto(
        textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.bold)),
    bodyLarge: GoogleFonts.roboto(
        textStyle: const TextStyle(color: Colors.black, fontSize: 16)),
    bodyMedium: GoogleFonts.roboto(
        textStyle: const TextStyle(color: Colors.black, fontSize: 14)),
    bodySmall: GoogleFonts.roboto(
        textStyle: const TextStyle(color: Colors.black, fontSize: 12)),
  );
*/
  IconThemeData iconTheme() {
    return const IconThemeData(color: Colors.white, shadows: [
    ]);
  }

  IconThemeData iconThemeReverse() {
    return const IconThemeData(color: Colors.black, shadows: [
    ]);
  }

  InputDecorationTheme inputDecorationTheme() {
    return InputDecorationTheme(
      focusColor: Colors.white,
      fillColor: Colors.white,
      suffixIconColor: Colors.white,
      prefixIconColor: Colors.white,
      iconColor: Colors.white,
      hoverColor: Colors.white,
      labelStyle: textTheme().labelLarge,
      counterStyle: textTheme().bodyMedium,
      prefixStyle: textTheme().bodyMedium,
      suffixStyle: textTheme().bodyMedium,
      errorStyle: textTheme().labelMedium?.copyWith(
          inherit: true, color: Colors.white),
      hintStyle: textTheme().bodySmall,
      helperStyle: textTheme().bodySmall,
      floatingLabelAlignment: FloatingLabelAlignment.center,
      helperMaxLines: 3,
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.all(5),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Colors.white,
              width: 1
          )
      ),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Colors.white,
              width: 1
          )
      ),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Colors.cyanAccent,
              width: 2
          )
      ),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Colors.grey,
              width: 1
          )
      ),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Color(0xFFD50000),
              width: 1
          )
      ),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Colors.red,
              width: 2
          )
      ),
    );
  }

  /*
  IconThemeData iconTheme2 = const IconThemeData(color: Colors.black, shadows: [
    BoxShadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 4)
  ]);
*/


  Widget circleAvatar(ImageProvider imageProvider, double size) {
    return CircleAvatar(
      child: ClipOval(
        child: Image(
          height: size,
          width: size,
          image: imageProvider,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  ButtonStyle positiveButtonStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.black,
      backgroundColor: Colors.green,
      minimumSize: const Size(88, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }

  ButtonStyle negativeButtonStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.black,
      backgroundColor: Colors.red[900],
      minimumSize: const Size(88, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }

  ButtonStyle warningButtonStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.black,
      backgroundColor: Colors.amber[800],
      minimumSize: const Size(88, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }

  ButtonStyle infoButtonStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.black,
      backgroundColor: Colors.blue,
      minimumSize: const Size(88, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }
}

