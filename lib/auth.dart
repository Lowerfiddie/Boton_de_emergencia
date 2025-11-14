import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

const String kAppsScriptUrl = 'https://script.google.com/macros/s/AKfycbxrNZoPn61pqP9GGub7Smk4Xah7f2ztAf27U_THp0H3XZGULoWSoR6qzNkNVu2cMnhdhA/exec';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: <String>[
    'email',
    'profile',
    'openid',
    sheets.SheetsApi.spreadsheetsScope, // lectura/escritura de Sheets
  ],
);