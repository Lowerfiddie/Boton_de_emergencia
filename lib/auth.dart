import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

const String kAppsScriptUrl = 'https://script.google.com/macros/s/AKfycbxvtSotumchxk_rN7VR-UsT3DlBciDXuo5vgPcTep8cU3YWnJJZllM7HMN91lderUkXiw/exec';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: <String>[
    'email',
    'profile',
    'openid',
    sheets.SheetsApi.spreadsheetsScope, // lectura/escritura de Sheets
  ],
);