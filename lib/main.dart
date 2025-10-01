// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs, avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
//import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';


/// To run this example, replace this value with your client ID, and/or
/// update the relevant configuration files, as described in the README.
String? clientId;

/// To run this example, replace this value with your server client ID, and/or
/// update the relevant configuration files, as described in the README.
String? serverClientId;

/// The scopes required by this application.
// #docregion CheckAuthorization
const List<String> scopes = <String>[
  'https://www.googleapis.com/auth/drive.file', // Lo mantienes por si acaso
  'https://www.googleapis.com/auth/spreadsheets', // Permiso completo para hojas de cálculo
];

void main() {
  runApp(const MaterialApp(title: 'Demo_Boton_de_emergencia', home: EmergencyButton()));
}

/// The SignInDemo app.
class EmergencyButton extends StatefulWidget {
  ///
  const EmergencyButton({super.key});

  @override
  State createState() => _EmergencyButtonState();
}

class _EmergencyButtonState extends State<EmergencyButton> {
  GoogleSignInAccount? _currentUser;
  bool _isAuthorized = false; // has granted permissions?
  String _errorMessage = '';
  String _serverAuthCode = '';

  @override
  void initState() {
    super.initState();

    // #docregion Setup
    // SIMPLIFICA LA INICIALIZACIÓN
    final GoogleSignIn signIn = GoogleSignIn.instance;
    unawaited(
      // ¡YA NO PASES clientId NI serverClientId AQUÍ!
      signIn.initialize().then((_) {
        signIn.authenticationEvents
            .listen(_handleAuthenticationEvent)
            .onError(_handleAuthenticationError);

        signIn.attemptLightweightAuthentication();
      }),
    );
    // #enddocregion Setup
  }

  Future<void> _handleAuthenticationEvent(
      GoogleSignInAuthenticationEvent event,
      ) async {
    // #docregion CheckAuthorization
    final GoogleSignInAccount? user = // ...
    // #enddocregion CheckAuthorization
    switch (event) {
      GoogleSignInAuthenticationEventSignIn() => event.user,
      GoogleSignInAuthenticationEventSignOut() => null,
    };

    // Check for existing authorization.
    // #docregion CheckAuthorization
    final GoogleSignInClientAuthorization? authorization = await user
        ?.authorizationClient
        .authorizationForScopes(scopes);
    // #enddocregion CheckAuthorization

    setState(() {
      _currentUser = user;
      _isAuthorized = authorization != null;
      _errorMessage = '';
    });
  }

  Future<void> _handleAuthenticationError(Object e) async {
    setState(() {
      _currentUser = null;
      _isAuthorized = false;
      _errorMessage = e is GoogleSignInException
          ? _errorMessageFromSignInException(e)
          : 'Unknown error: $e';
    });
  }

  // Prompts the user to authorize `scopes`.
  //
  // If authorizationRequiresUserInteraction() is true, this must be called from
  // a user interaction (button click). In this example app, a button is used
  // regardless, so authorizationRequiresUserInteraction() is not checked.
  Future<void> _handleAuthorizeScopes(GoogleSignInAccount user) async {
    try {
      // #docregion RequestScopes
      final GoogleSignInClientAuthorization? authorization = await user
          .authorizationClient
          .authorizeScopes(scopes);
      // #enddocregion RequestScopes

      // The returned tokens are ignored since this example uses the
      // authorizationHeaders method to re-read the token cached by
      // authorizeScopes.
      if (authorization != null) {
        setState(() {
          _isAuthorized = true;
          _errorMessage = '';
        });
      }
    } on GoogleSignInException catch (e) {
      setState(() {
        _errorMessage = _errorMessageFromSignInException(e);
      });
    }
  }

  // Requests a server auth code for the authorized scopes.
  //
  // If authorizationRequiresUserInteraction() is true, this must be called from
  // a user interaction (button click). In this example app, a button is used
  // regardless, so authorizationRequiresUserInteraction() is not checked.
  Future<void> _handleGetAuthCode(GoogleSignInAccount user) async {
    try {
      // #docregion RequestServerAuth
      final GoogleSignInServerAuthorization? serverAuth =
      await user.authorizationClient.authorizeServer(scopes);
      // #enddocregion RequestServerAuth

      setState(() {
        _serverAuthCode = serverAuth == null ? '' : serverAuth.serverAuthCode;
      });
    } on GoogleSignInException catch (e) {
      setState(() {
        _errorMessage = _errorMessageFromSignInException(e);
      });
    }
  }

  Future<void> _handleSignOut() async {
    // Disconnect instead of just signing out, to reset the example state as
    // much as possible.
    await GoogleSignIn.instance.disconnect();
  }

  Widget _buildBody() {
    final GoogleSignInAccount? user = _currentUser;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        if (user != null)
          ..._buildAuthenticatedWidgets(user)
        else
          ..._buildUnauthenticatedWidgets(),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  /// Returns the list of widgets to include if the user is authenticated.
  List<Widget> _buildAuthenticatedWidgets(GoogleSignInAccount user) {
    return <Widget>[
      // The user is Authenticated.
      ListTile(
        leading: GoogleUserCircleAvatar(identity: user),
        title: Text(user.displayName ?? ''),
        subtitle: Text(user.email),
      ),
      const Text('Signed in successfully.'),
      if (_isAuthorized) ...<Widget>[
        // The user has Authorized all required scopes.
        // TODO: Add logic for authorized user, e.g., calling an API.
        if (_serverAuthCode.isEmpty)
          ElevatedButton(
            child: const Text('REQUEST SERVER AUTH CODE'),
            onPressed: () => _handleGetAuthCode(user),
          )
        else
          SelectableText('Server auth code:\n$_serverAuthCode\n'),
      ] else ...<Widget>[
        // The user has NOT Authorized all required scopes.
        const Text(
            'Additional permissions are needed to interact with your spreadsheets.'),
        ElevatedButton(
          onPressed: () => _handleAuthorizeScopes(user),
          child: const Text('REQUEST PERMISSIONS'),
        ),
      ],
      ElevatedButton(onPressed: _handleSignOut, child: const Text('SIGN OUT')),
    ];
  }

  /// Returns the list of widgets to include if the user is not authenticated.
  List<Widget> _buildUnauthenticatedWidgets() {
    return <Widget>[
      const Text('You are not currently signed in.'),
      // #docregion ExplicitSignIn
      if (GoogleSignIn.instance.supportsAuthenticate())
        ElevatedButton(
          onPressed: () async {
            try {
              await GoogleSignIn.instance.authenticate();
            } on GoogleSignInException catch (e) {
              setState(() {
                _errorMessage = _errorMessageFromSignInException(e);
              });
            } catch (e) {
              setState(() {
                _errorMessage = 'An unknown error occurred: $e';
              });
            }
          },
          child: const Text('SIGN IN'),
        )
      else
        const Text(
            'This platform does not support interactive sign-in flows.'),
      // #enddocregion ExplicitSignIn
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Sign In')),
      body: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: _buildBody(),
      ),
    );
  }

  String _errorMessageFromSignInException(GoogleSignInException e) {
    // En la práctica, una aplicación probablemente debería tener un manejo específico para la mayoría
    // o todos los casos, pero por simplicidad esto solo maneja la cancelación e informa
    // el resto como errores genéricos.
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Inicio de sesión cancelado por el usuario.';
      default:
        return 'GoogleSignInException ${e.code}: ${e.description}';
    }
  }
}
