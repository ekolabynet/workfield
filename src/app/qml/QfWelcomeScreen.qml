import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Particles
import QtCore
import org.qfield.core
import org.qfield.gui
import Qt.labs.folderlistmodel
import Theme

/**
 * \ingroup qml
 */
Page {
  id: welcomeScreen

  property bool firstShown: false

  property alias model: table.model

  signal showAbout
  signal showLocalDataPicker
  signal showQFieldCloudScreen
  signal showSettings
  signal showProjectCreationScreen

  visible: false
  focus: visible

  function templatesDataRoot() {
    return iface.dataRoot();
  }

  function createProjectFromTemplate(templatePath, projectName) {
    const root = templatesDataRoot();
    if (root === "") {
      return;
    }
    // WorkFieldGIS 22.10.2026 — miejsce z wyboru (pamięć telefonu / karta SD); katalog zakłada C++.
    const safeName = FileUtils.sanitizeFilePathPart(projectName);
    const destination = iface.katalogNowychProjektow() + "/" + safeName;
    if (FileUtils.fileExists(destination + "/projekt.qgs") || FileUtils.fileExists(destination + "/projekt.qgz")) {
      displayToast(qsTr("Projekt o nazwie '%1' już istnieje").arg(safeName));
      return;
    }
    if (!FileUtils.copyRecursively(templatePath, destination)) {
      displayToast(qsTr("Nie udało się skopiować szablonu"));
      return;
    }
    if (FileUtils.fileExists(destination + "/projekt.qgs")) {
      iface.loadFile(destination + "/projekt.qgs", projectName);
    } else if (FileUtils.fileExists(destination + "/projekt.qgz")) {
      iface.loadFile(destination + "/projekt.qgz", projectName);
    } else {
      displayToast(qsTr("Szablon nie zawiera pliku projekt.qgs"));
    }
  }

  Settings {
    id: registry
    category: 'QField'

    property string baseMapProject: ''
    property string defaultProject: ''
    property bool loadProjectOnLaunch: false
  }

  Rectangle {
    id: welcomeBackground
    anchors.fill: parent
    color: Theme.darkTheme ? "#062e2a" : "#00695c"
  }

  // ── WZÓR STARTOWY (WorkFieldGIS 19.10.2026 [WF-WZOR-STARTOWY]) ──────────
  // Decyzje Piotra 18:08–18:27: prawdziwe działki u góry przechodzą w warstwice
  // na dole, jasne szrafury na zieleni; co 0,5 s rozjaśnia się kolejno jedna
  // warstwica (od zewnętrznej), potem pojedyncze działki. Działki: wycinek
  // z sample_lots.gpkg, TYLKO geometria (500 × 1028 m, ok. 160 działek, bez największych), wsp.
  // znormalizowane 0..1. Kierunki szraf i położenie warstwic liczone z nazwy
  // wersji — każda nazwa kodowa wygląda trochę inaczej (claude/EKRAN_STARTOWY_plan.md).
  // [WF-WZOR-INTRO] 19.10.2026 18:49 — Piotr: „2 sekundy ekranu z szybką animacją,
  // ciemniejszego, a potem pokażmy wersję — z logo i nazwą kodową na dole z boku,
  // a tło ciemne bez szrafu, albo tylko lokalnie w okolicy ikony i nazwy kodowej”.
  // Intro: cały wzór, krok co 110 ms, na środku logo, nazwa, wersja; dotknięcie
  // pomija. Potem wzór zostaje tylko wokół plakietki wersji w prawym dolnym rogu.
  Item {
    id: wzorStartowy
    anchors.fill: parent

    readonly property var dzialki: [[0.591,0.125,0.635,0.117,0.68,0.11,0.725,0.102,0.769,0.094,0.812,0.087,0.819,0.088,0.813,0.076,0.375,0.152,0.375,0.163,0.412,0.156,0.456,0.148,0.501,0.141,0.546,0.133,0.591,0.125],[0.827,0.108,0.819,0.088,0.812,0.087,0.769,0.094,0.786,0.116,0.827,0.108],[0.786,0.116,0.769,0.094,0.725,0.102,0.741,0.124,0.786,0.116],[0.823,0.188,0.805,0.163,0.758,0.171,0.776,0.196,0.823,0.188],[0.891,0.203,0.871,0.18,0.823,0.188,0.843,0.215,0.888,0.208,0.891,0.203],[0.871,0.18,0.85,0.155,0.849,0.155,0.805,0.163,0.823,0.188,0.871,0.18],[0.436,0.032,0.438,0.037,0.451,0.036,0.458,0.052,0.493,0.049,0.528,0.045,0.522,0.031,0.515,0.029,0.513,0.024,0.447,0.031,0.436,0.032],[0.92,0.138,1.102,0.107,1.098,0.102,1.077,0.074,1.065,0.076,0.884,0.107,0.853,0.112,0.847,0.113,0.862,0.148,0.92,0.138],[0.805,0.163,0.849,0.155,0.841,0.153,0.803,0.16,0.805,0.163],[0.894,0.176,0.874,0.153,0.878,0.148,0.923,0.14,0.92,0.138,0.862,0.148,0.852,0.149,0.706,0.175,0.708,0.177,0.756,0.168,0.803,0.16,0.841,0.153,0.849,0.155,0.85,0.155,0.871,0.18,0.891,0.203,0.888,0.208,0.843,0.215,0.795,0.223,0.749,0.231,0.75,0.233,0.977,0.195,0.976,0.193,0.924,0.202,0.914,0.2,0.894,0.176],[0.795,0.223,0.776,0.196,0.728,0.204,0.729,0.205,0.749,0.231,0.795,0.223],[0.776,0.196,0.758,0.171,0.756,0.168,0.708,0.177,0.728,0.204,0.776,0.196],[0.634,0.183,0.851,0.146,0.834,0.107,0.827,0.108,0.786,0.116,0.741,0.124,0.696,0.131,0.651,0.139,0.607,0.147,0.634,0.183],[0.374,0.229,0.634,0.183,0.607,0.147,0.562,0.155,0.517,0.162,0.472,0.17,0.428,0.178,0.375,0.187,0.374,0.229],[0.834,0.107,0.82,0.075,0.813,0.076,0.819,0.088,0.827,0.108,0.834,0.107],[0.531,0.022,0.527,0.013,0.523,0.003,0.516,0.004,0.377,0.018,0.377,0.038,0.436,0.032,0.447,0.031,0.513,0.024,0.531,0.022],[0.878,0.1,0.911,0.095,0.889,0.064,0.849,0.071,0.878,0.1],[0.85,0.105,0.878,0.1,0.849,0.071,0.837,0.073,0.85,0.105],[0.83,0.074,0.847,0.113,0.853,0.112,0.85,0.105,0.837,0.073,0.83,0.074],[0.85,0.105,0.853,0.112,0.884,0.107,0.878,0.1,0.85,0.105],[0.878,0.1,0.884,0.107,1.065,0.076,1.059,0.067,1.036,0.071,1.032,0.075,0.911,0.095,0.878,0.1],[-0.085,0.3,-0.076,0.309,0.105,0.268,0.1,0.263,-0.085,0.3],[0.681,0.213,0.662,0.188,0.615,0.196,0.634,0.222,0.681,0.213],[0.472,0.221,0.519,0.213,0.517,0.21,0.47,0.218,0.472,0.221],[0.217,0.084,0.227,0.121,0.248,0.12,0.299,0.118,0.299,0.08,0.217,0.084],[0.565,0.202,0.613,0.193,0.66,0.185,0.708,0.177,0.706,0.175,0.374,0.233,0.374,0.235,0.422,0.226,0.47,0.218,0.517,0.21,0.565,0.202],[1.033,0.185,1.335,0.132,1.333,0.13,1.321,0.132,1.268,0.141,1.215,0.151,1.159,0.161,1.108,0.17,1.044,0.181,0.982,0.192,0.976,0.193,0.977,0.195,1.033,0.185],[0.885,0.352,0.898,0.367,1.033,0.347,1.021,0.333,0.993,0.33,0.933,0.342,0.885,0.352],[0.424,0.229,0.472,0.221,0.47,0.218,0.422,0.226,0.424,0.229],[0.374,0.238,0.424,0.229,0.422,0.226,0.374,0.235,0.374,0.238],[0.728,0.204,0.708,0.177,0.66,0.185,0.662,0.188,0.681,0.213,0.729,0.205,0.728,0.204],[0.615,0.196,0.662,0.188,0.66,0.185,0.613,0.193,0.615,0.196],[0.567,0.204,0.615,0.196,0.613,0.193,0.565,0.202,0.567,0.204],[0.248,0.12,0.248,0.122,0.309,0.121,0.31,0.118,0.299,0.118,0.248,0.12],[0.014,0.172,0.029,0.188,0.309,0.168,0.309,0.158,0.262,0.16,0.246,0.162,0.033,0.17,0.014,0.172],[0.307,0.265,0.309,0.226,0.297,0.228,0.296,0.267,0.307,0.265],[0.741,0.124,0.725,0.102,0.68,0.11,0.696,0.131,0.741,0.124],[0.696,0.131,0.68,0.11,0.635,0.117,0.651,0.139,0.696,0.131],[0.299,0.08,0.299,0.118,0.31,0.118,0.31,0.08,0.299,0.08],[-0.178,0.202,-0.158,0.224,0.044,0.203,0.029,0.188,-0.178,0.202],[-0.116,0.268,-0.085,0.3,0.1,0.263,0.073,0.235,-0.116,0.268],[-0.202,0.177,-0.198,0.181,0.014,0.172,-0.021,0.136,-0.202,0.177],[-0.198,0.181,-0.178,0.202,0.029,0.188,0.014,0.172,-0.198,0.181],[0.786,-0.003,0.778,-0.022,0.687,-0.013,0.65,-0.01,0.659,0.009,0.78,-0.003,0.786,-0.003],[0.659,0.009,0.65,-0.01,0.604,-0.005,0.523,0.003,0.527,0.013,0.531,0.022,0.603,0.015,0.659,0.009],[0.868,-0.002,0.855,-0.031,0.797,-0.025,0.809,0.004,0.868,-0.002],[0.913,0.291,0.903,0.276,0.865,0.283,0.875,0.298,0.888,0.315,0.926,0.308,0.913,0.291],[0.951,0.284,0.942,0.27,0.903,0.276,0.913,0.291,0.926,0.308,0.962,0.302,0.952,0.286,0.951,0.284],[0.377,0.038,0.377,0.046,0.382,0.045,0.411,0.04,0.438,0.037,0.436,0.032,0.377,0.038],[0.31,0.08,0.311,-0.022,0.312,-0.037,0.298,-0.036,0.298,-0.017,0.3,0.007,0.299,0.08,0.31,0.08],[0.044,0.203,0.058,0.219,0.309,0.184,0.309,0.177,0.044,0.203],[0.058,0.219,0.073,0.235,0.297,0.194,0.309,0.192,0.309,0.184,0.058,0.219],[0.377,0.046,0.377,0.06,0.442,0.054,0.458,0.052,0.451,0.036,0.438,0.037,0.411,0.04,0.382,0.045,0.377,0.046],[-0.081,-0.02,-0.04,0.087,0.101,0.055,0.025,-0.025,-0.081,-0.02],[-0.04,0.087,-0.037,0.095,0.217,0.084,0.299,0.08,0.3,0.007,0.298,-0.017,0.298,-0.036,0.025,-0.025,0.101,0.055,-0.04,0.087],[0.837,0.304,0.827,0.289,0.771,0.299,0.782,0.314,0.795,0.331,0.805,0.329,0.85,0.321,0.837,0.304],[0.875,0.298,0.865,0.283,0.827,0.289,0.837,0.304,0.85,0.321,0.888,0.315,0.875,0.298],[0.889,0.064,0.911,0.095,1.032,0.075,1.036,0.071,1.059,0.067,1.05,0.054,1.07,0.05,1.059,0.036,0.889,0.064],[0.821,0.032,0.88,0.026,0.868,-0.002,0.809,0.004,0.82,0.028,0.821,0.032],[0.758,0.171,0.805,0.163,0.803,0.16,0.756,0.168,0.758,0.171],[0.695,0.277,0.676,0.251,0.638,0.258,0.657,0.283,0.67,0.281,0.695,0.277],[0.581,0.296,0.561,0.269,0.531,0.274,0.53,0.274,0.55,0.302,0.581,0.296],[0.651,0.139,0.635,0.117,0.591,0.125,0.607,0.147,0.651,0.139],[0.607,0.147,0.591,0.125,0.546,0.133,0.562,0.155,0.607,0.147],[0.562,0.155,0.546,0.133,0.501,0.141,0.517,0.162,0.562,0.155],[0.813,0.035,0.775,-0.053,0.767,-0.071,0.758,-0.07,0.769,-0.044,0.778,-0.022,0.786,-0.003,0.788,-0.0,0.801,0.031,0.804,0.037,0.82,0.075,0.834,0.107,0.851,0.146,0.852,0.149,0.862,0.148,0.847,0.113,0.83,0.074,0.813,0.035],[0.993,0.33,1.021,0.333,1.014,0.326,0.993,0.33],[0.472,0.17,0.456,0.148,0.412,0.156,0.428,0.178,0.472,0.17],[0.959,0.284,0.95,0.269,0.95,0.268,0.949,0.266,0.941,0.268,0.942,0.27,0.951,0.284,0.952,0.286,0.959,0.285,0.959,0.284],[0.987,0.297,0.97,0.283,0.959,0.284,0.959,0.285,0.969,0.3,0.987,0.297],[0.376,0.106,0.804,0.037,0.801,0.031,0.752,0.039,0.711,0.046,0.669,0.053,0.628,0.059,0.596,0.065,0.567,0.069,0.513,0.078,0.464,0.086,0.376,0.1,0.376,0.106],[0.567,0.069,0.549,0.043,0.528,0.045,0.493,0.049,0.513,0.078,0.567,0.069],[0.513,0.078,0.493,0.049,0.458,0.052,0.442,0.054,0.453,0.07,0.464,0.086,0.513,0.078],[0.428,0.178,0.412,0.156,0.375,0.163,0.375,0.187,0.428,0.178],[0.711,0.046,0.686,0.01,0.66,0.012,0.642,0.014,0.669,0.053,0.711,0.046],[0.669,0.053,0.642,0.014,0.604,0.018,0.612,0.037,0.628,0.059,0.669,0.053],[0.627,0.315,0.63,0.318,0.807,0.288,0.805,0.285,0.746,0.295,0.687,0.305,0.627,0.315],[0.373,0.298,0.584,0.262,0.697,0.242,0.75,0.233,0.749,0.231,0.701,0.24,0.653,0.248,0.605,0.256,0.582,0.26,0.557,0.264,0.509,0.272,0.461,0.28,0.373,0.296,0.373,0.298],[0.401,0.354,0.384,0.33,0.335,0.338,0.334,0.369,0.404,0.357,0.401,0.354],[0.634,0.222,0.615,0.196,0.567,0.204,0.586,0.23,0.634,0.222],[0.605,0.256,0.586,0.23,0.538,0.238,0.557,0.264,0.582,0.26,0.605,0.256],[0.557,0.264,0.538,0.238,0.49,0.247,0.509,0.272,0.557,0.264],[0.029,0.188,0.044,0.203,0.309,0.177,0.309,0.168,0.029,0.188],[0.749,0.231,0.729,0.205,0.681,0.213,0.701,0.24,0.749,0.231],[0.888,0.244,0.869,0.217,0.791,0.23,0.792,0.231,0.811,0.257,0.888,0.244],[0.657,0.283,0.638,0.258,0.637,0.256,0.623,0.258,0.561,0.269,0.581,0.296,0.61,0.291,0.657,0.283],[0.509,0.272,0.49,0.247,0.443,0.255,0.461,0.28,0.509,0.272],[0.729,0.271,0.746,0.295,0.805,0.285,0.788,0.261,0.784,0.262,0.764,0.265,0.734,0.27,0.729,0.271],[0.55,0.302,0.53,0.274,0.477,0.284,0.498,0.311,0.541,0.303,0.55,0.302],[0.968,0.23,0.946,0.205,0.944,0.204,0.869,0.217,0.888,0.244,0.896,0.242,0.968,0.23],[0.538,0.238,0.519,0.213,0.472,0.221,0.49,0.247,0.538,0.238],[0.586,0.23,0.567,0.204,0.519,0.213,0.538,0.238,0.586,0.23],[0.764,0.265,0.745,0.239,0.715,0.244,0.734,0.27,0.764,0.265],[0.676,0.251,0.715,0.244,0.714,0.243,0.676,0.249,0.664,0.252,0.637,0.256,0.638,0.258,0.676,0.251],[0.701,0.24,0.681,0.213,0.634,0.222,0.653,0.248,0.701,0.24],[0.653,0.248,0.634,0.222,0.586,0.23,0.605,0.256,0.653,0.248],[0.734,0.27,0.715,0.244,0.676,0.251,0.695,0.277,0.729,0.271,0.734,0.27],[0.461,0.28,0.443,0.255,0.374,0.267,0.373,0.296,0.461,0.28],[0.443,0.255,0.424,0.229,0.374,0.238,0.374,0.267,0.443,0.255],[0.49,0.247,0.472,0.221,0.424,0.229,0.443,0.255,0.49,0.247],[0.811,0.257,0.792,0.231,0.765,0.236,0.769,0.24,0.775,0.249,0.784,0.262,0.788,0.261,0.811,0.257],[0.784,0.262,0.775,0.249,0.769,0.24,0.765,0.236,0.745,0.239,0.764,0.265,0.784,0.262],[0.745,0.239,0.765,0.236,0.792,0.231,0.791,0.23,0.714,0.243,0.715,0.244,0.745,0.239],[0.687,-0.013,0.677,-0.035,0.633,-0.031,0.582,-0.025,0.53,-0.02,0.507,-0.018,0.516,0.004,0.523,0.003,0.604,-0.005,0.65,-0.01,0.687,-0.013],[0.377,0.018,0.516,0.004,0.507,-0.018,0.479,-0.015,0.378,-0.005,0.377,0.018],[0.464,0.086,0.453,0.07,0.376,0.082,0.376,0.1,0.464,0.086],[0.375,0.152,0.813,0.076,0.82,0.075,0.804,0.037,0.376,0.106,0.375,0.152],[0.745,0.32,0.734,0.305,0.688,0.313,0.7,0.328,0.712,0.345,0.757,0.338,0.745,0.32],[0.517,0.162,0.501,0.141,0.456,0.148,0.472,0.17,0.517,0.162],[0.788,-0.0,0.786,-0.003,0.78,-0.003,0.781,0.0,0.788,-0.0],[0.686,0.01,0.737,0.005,0.781,0.0,0.78,-0.003,0.659,0.009,0.66,0.012,0.686,0.01],[0.642,0.014,0.66,0.012,0.659,0.009,0.603,0.015,0.604,0.018,0.642,0.014],[-0.158,0.224,-0.137,0.245,0.058,0.219,0.044,0.203,-0.158,0.224],[-0.137,0.245,-0.116,0.268,0.073,0.235,0.058,0.219,-0.137,0.245],[0.843,0.215,0.823,0.188,0.776,0.196,0.795,0.223,0.843,0.215],[1.044,0.181,1.003,0.127,0.937,0.138,0.96,0.165,0.982,0.192,1.044,0.181],[0.96,0.165,0.937,0.138,0.923,0.14,0.949,0.167,0.96,0.165],[0.95,0.268,0.982,0.263,0.989,0.262,0.988,0.26,0.949,0.266,0.95,0.268],[0.1,0.263,0.297,0.228,0.297,0.194,0.073,0.235,0.1,0.263],[0.309,0.226,0.309,0.192,0.297,0.194,0.297,0.228,0.309,0.226],[0.558,0.327,0.541,0.303,0.498,0.311,0.49,0.312,0.507,0.336,0.517,0.334,0.558,0.327],[0.627,0.315,0.61,0.291,0.581,0.296,0.55,0.302,0.541,0.303,0.558,0.327,0.627,0.315],[0.821,0.032,0.82,0.028,0.809,0.004,0.797,-0.025,0.784,-0.053,0.775,-0.053,0.813,0.035,0.828,0.05,0.821,0.032],[0.976,0.193,0.949,0.167,0.894,0.176,0.914,0.2,0.924,0.202,0.976,0.193],[1.003,0.127,1.068,0.116,1.104,0.11,1.105,0.111,1.12,0.109,1.122,0.106,1.175,0.098,1.228,0.088,1.281,0.079,1.292,0.078,1.29,0.075,1.102,0.107,0.92,0.138,0.923,0.14,0.937,0.138,1.003,0.127],[0.422,0.293,0.442,0.32,0.49,0.312,0.498,0.311,0.477,0.284,0.467,0.285,0.44,0.29,0.434,0.291,0.422,0.293],[0.849,0.071,0.828,0.05,0.813,0.035,0.83,0.074,0.837,0.073,0.849,0.071],[1.01,0.293,0.993,0.279,0.97,0.283,0.987,0.297,1.01,0.293],[1.04,0.253,1.096,0.243,1.124,0.238,1.15,0.232,0.988,0.26,0.989,0.262,1.04,0.253],[0.61,0.291,0.627,0.315,0.687,0.305,0.67,0.281,0.657,0.283,0.61,0.291],[0.67,0.281,0.687,0.305,0.746,0.295,0.729,0.271,0.695,0.277,0.67,0.281],[0.949,0.167,0.923,0.14,0.878,0.148,0.874,0.153,0.894,0.176,0.949,0.167],[0.404,0.357,0.579,0.327,0.63,0.318,0.627,0.315,0.558,0.327,0.517,0.334,0.507,0.336,0.401,0.354,0.404,0.357],[0.915,0.269,0.896,0.242,0.888,0.244,0.811,0.257,0.788,0.261,0.805,0.285,0.807,0.288,0.818,0.286,0.915,0.269],[0.513,0.024,0.515,0.029,0.522,0.031,0.528,0.045,0.549,0.043,0.581,0.04,0.612,0.037,0.604,0.018,0.603,0.015,0.531,0.022,0.513,0.024],[0.336,0.308,0.335,0.338,0.384,0.33,0.387,0.33,0.372,0.307,0.36,0.304,0.341,0.307,0.336,0.308],[0.36,0.304,0.372,0.307,0.387,0.33,0.442,0.32,0.422,0.293,0.379,0.301,0.36,0.304],[0.982,0.192,0.96,0.165,0.949,0.167,0.976,0.193,0.982,0.192],[0.507,0.336,0.49,0.312,0.442,0.32,0.387,0.33,0.384,0.33,0.401,0.354,0.507,0.336],[1.04,0.217,1.022,0.192,0.946,0.205,0.968,0.23,0.999,0.225,1.009,0.223,1.04,0.217],[0.61,0.344,0.599,0.328,0.554,0.336,0.566,0.352,0.579,0.369,0.623,0.361,0.61,0.344],[0.655,0.336,0.644,0.321,0.599,0.328,0.61,0.344,0.623,0.361,0.667,0.353,0.655,0.336],[0.7,0.328,0.688,0.313,0.644,0.321,0.655,0.336,0.667,0.353,0.712,0.345,0.7,0.328],[1.028,0.247,1.009,0.223,0.999,0.225,1.022,0.248,1.028,0.247],[0.99,0.255,1.023,0.249,1.022,0.248,0.99,0.254,0.99,0.255],[0.969,0.282,0.963,0.277,0.956,0.278,0.962,0.284,0.969,0.282],[0.963,0.277,0.956,0.27,0.95,0.269,0.959,0.284,0.97,0.283,0.969,0.282,0.962,0.284,0.956,0.278,0.963,0.277],[0.686,0.01,0.711,0.046,0.752,0.039,0.737,0.005,0.686,0.01],[0.737,0.005,0.752,0.039,0.801,0.031,0.788,-0.0,0.781,0.0,0.737,0.005],[0.581,0.04,0.584,0.045,0.59,0.054,0.591,0.056,0.593,0.061,0.595,0.063,0.596,0.065,0.628,0.059,0.612,0.037,0.581,0.04],[0.567,0.069,0.596,0.065,0.595,0.063,0.593,0.061,0.591,0.056,0.59,0.054,0.584,0.045,0.581,0.04,0.549,0.043,0.567,0.069],[0.782,0.314,0.771,0.299,0.734,0.305,0.745,0.32,0.757,0.338,0.795,0.331,0.782,0.314],[1.022,0.248,0.999,0.225,0.968,0.23,0.99,0.254,1.022,0.248],[1.01,0.293,1.024,0.291,1.063,0.284,1.04,0.253,0.989,0.262,0.982,0.263,0.979,0.266,0.993,0.279,1.01,0.293],[0.946,0.205,1.022,0.192,1.021,0.19,0.973,0.199,0.944,0.204,0.946,0.205],[0.993,0.279,0.979,0.266,0.982,0.263,0.95,0.268,0.95,0.269,0.956,0.27,0.963,0.277,0.969,0.282,0.97,0.283,0.993,0.279],[0.566,0.352,0.554,0.336,0.522,0.341,0.51,0.344,0.522,0.359,0.535,0.377,0.579,0.369,0.566,0.352],[0.519,0.213,0.567,0.204,0.565,0.202,0.517,0.21,0.519,0.213],[0.453,0.07,0.442,0.054,0.377,0.06,0.376,0.082,0.453,0.07],[0.99,0.254,0.968,0.23,0.896,0.242,0.915,0.269,0.99,0.255,0.99,0.254]]
    readonly property string ziarnoTekst: typeof appVersionStr !== "undefined" ? appVersionStr : "WorkFieldGIS"
    property int krok: -1
    property bool introTrwa: true
    property bool introZrobione: false
    readonly property real plakietkaX: width - 96
    readonly property real plakietkaY: height - mainWindow.sceneBottomMargin - 40

    function startIntro() {
      if (introZrobione)
        return;
      introZrobione = true;
      wzorStartowy.introTrwa = true;
      console.log("WFG intro: start");
    }
    function zakonczIntro() {
      if (wzorStartowy.introTrwa)
        console.log("WFG intro: koniec");
      wzorStartowy.introTrwa = false;
      plotnoDzialek.requestPaint();
      plotnoWarstwic.requestPaint();
    }

    Timer {
      id: koniecIntra
      // [WF-WZOR-INTRO] chodzi zawsze, gdy intro trwa — nie zależy od restart()
      interval: 2000
      running: wzorStartowy.introTrwa
      onTriggered: wzorStartowy.zakonczIntro()
    }
    Connections {
      target: welcomeScreen
      function onVisibleChanged() {
        if (welcomeScreen.visible)
          wzorStartowy.startIntro();
      }
    }
    readonly property int liczbaWarstwic: 12
    property var kolejDzialek: []
    property var katy: []

    function losowe(ziarno) {
      let s = ziarno >>> 0;
      return function () {
        s = (s * 1664525 + 1013904223) >>> 0;
        return s / 4294967296;
      };
    }
    function hash(t) {
      let h = 2166136261;
      for (let i = 0; i < t.length; i++)
        h = Math.imul(h ^ t.charCodeAt(i), 16777619);
      return h >>> 0;
    }
    function maskaPlakietki(ctx) {
      const m = ctx.createRadialGradient(plakietkaX, plakietkaY, 0, plakietkaX, plakietkaY, 150);
      m.addColorStop(0.0, "rgba(0,0,0,0.9)");
      m.addColorStop(1.0, "rgba(0,0,0,0)");
      return m;
    }
    function skala(w, h) {
      return Math.max(w, h / 2.056);
    }

    Component.onCompleted: {
      const r = losowe(hash(ziarnoTekst));
      const k = [];
      for (let i = 0; i < dzialki.length; i++)
        k.push({ "wzor": [Qt.BDiagPattern, Qt.FDiagPattern, Qt.HorPattern, Qt.VerPattern, Qt.BDiagPattern, Qt.FDiagPattern][Math.floor(r() * 6)] });
      katy = k;
      const gora = [];
      for (let i = 0; i < dzialki.length; i++)
        if (dzialki[i][1] < 0.55)
          gora.push(i);
      for (let i = gora.length - 1; i > 0; i--) {
        const j = Math.floor(r() * (i + 1));
        const t = gora[i]; gora[i] = gora[j]; gora[j] = t;
      }
      kolejDzialek = gora.slice(0, 8);
      plotnoDzialek.requestPaint();
      plotnoWarstwic.requestPaint();
      if (welcomeScreen.visible)
        startIntro();
      else
        wzorStartowy.introTrwa = false;
    }

    Timer {
      interval: wzorStartowy.introTrwa ? 110 : 500
      repeat: true
      running: welcomeScreen.visible
      onTriggered: {
        wzorStartowy.krok = (wzorStartowy.krok + 1) % (wzorStartowy.liczbaWarstwic + wzorStartowy.kolejDzialek.length);
        plotnoDzialek.requestPaint();
        plotnoWarstwic.requestPaint();
      }
    }

    Canvas {
      id: plotnoDzialek
      anchors.fill: parent
      onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const s = wzorStartowy.skala(width, height);
        const ox = (width - s) / 2;
        const jasna = wzorStartowy.krok >= wzorStartowy.liczbaWarstwic ? wzorStartowy.kolejDzialek[wzorStartowy.krok - wzorStartowy.liczbaWarstwic] : -1;
        for (let i = 0; i < wzorStartowy.dzialki.length; i++) {
          const p = wzorStartowy.dzialki[i];
          const k = wzorStartowy.katy[i] || { "wzor": Qt.BDiagPattern };
          ctx.beginPath();
          for (let j = 0; j < p.length; j += 2) {
            const x = ox + p[j] * s, y = p[j + 1] * s * 2.056;
            if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
          }
          ctx.closePath();
          // Wzór szrafury z Qt (createPattern) zamiast clip(): Canvas w Qt
          // nie przycina linii do ścieżki niezawodnie (sprawdzone 19.10).
          const jas = i === jasna;
          ctx.fillStyle = ctx.createPattern(jas ? "#30ffffff" : "#0affffff", k.wzor);
          ctx.fill();
          ctx.strokeStyle = jas ? "rgba(255,255,255,0.38)" : "rgba(255,255,255,0.08)";
          ctx.lineWidth = jas ? 1.6 : 0.8;
          ctx.stroke();
        }
        // przenikanie: działki gasną ku dołowi
        ctx.globalCompositeOperation = "destination-in";
        const g = ctx.createLinearGradient(0, 0, 0, height);
        // [WF-WZOR-CIEMNIEJ] od góry też wygaszone — tam są przyciski i belka
        g.addColorStop(0.0, "rgba(0,0,0,0)");
        g.addColorStop(0.14, "rgba(0,0,0,0)");
        g.addColorStop(0.26, "rgba(0,0,0,1)");
        g.addColorStop(0.75, "rgba(0,0,0,0)");
        ctx.fillStyle = wzorStartowy.introTrwa ? g : wzorStartowy.maskaPlakietki(ctx);
        ctx.fillRect(0, 0, width, height);
      }
    }

    Canvas {
      id: plotnoWarstwic
      anchors.fill: parent
      onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const r = wzorStartowy.losowe(wzorStartowy.hash(wzorStartowy.ziarnoTekst) ^ 0x5bd1e995);
        const cx = width * (0.55 + r() * 0.35), cy = height * (0.72 + r() * 0.12);
        const faza = r() * 6.28;
        const jasna = wzorStartowy.krok >= 0 && wzorStartowy.krok < wzorStartowy.liczbaWarstwic ? wzorStartowy.liczbaWarstwic - 1 - wzorStartowy.krok : -1;
        const jednostka = Math.min(width, height) / 21;
        for (let k = 0; k < wzorStartowy.liczbaWarstwic; k++) {
          const rr0 = (k + 1) * jednostka;
          ctx.beginPath();
          for (let a = 0; a <= 360; a += 6) {
            const t = a * Math.PI / 180;
            const rr = rr0 * (1 + 0.18 * Math.sin(3 * t + k * 0.5 + faza) + 0.08 * Math.sin(5 * t));
            const x = cx + rr * Math.cos(t), y = cy + rr * 0.8 * Math.sin(t);
            if (a === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
          }
          const jas = k === jasna;
          ctx.strokeStyle = jas ? "rgba(255,255,255,0.38)" : (k % 5 === 4 ? "rgba(255,255,255,0.10)" : "rgba(255,255,255,0.055)");
          ctx.lineWidth = jas ? 1.8 : 1;
          ctx.stroke();
        }
        ctx.globalCompositeOperation = "destination-in";
        const g = ctx.createLinearGradient(0, 0, 0, height);
        g.addColorStop(0.5, "rgba(0,0,0,0)");
        g.addColorStop(0.92, "rgba(0,0,0,1)");
        ctx.fillStyle = wzorStartowy.introTrwa ? g : wzorStartowy.maskaPlakietki(ctx);
        ctx.fillRect(0, 0, width, height);
      }
    }
  
    // ── intro: na środku logo, nazwa i wersja (dotknięcie pomija) ──
    Rectangle {
      anchors.fill: parent
      z: 20
      color: welcomeBackground.color
      opacity: wzorStartowy.introTrwa ? 0.55 : 0
      visible: opacity > 0
      Behavior on opacity {
        NumberAnimation {
          duration: 400
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: wzorStartowy.introTrwa
        onClicked: wzorStartowy.zakonczIntro()
      }
    }
    Column {
      z: 21
      anchors.centerIn: parent
      spacing: 8
      opacity: wzorStartowy.introTrwa ? 1 : 0
      visible: opacity > 0
      Behavior on opacity {
        NumberAnimation {
          duration: 400
        }
      }
      Image {
        anchors.horizontalCenter: parent.horizontalCenter
        source: "qrc:/images/app_logo.svg"
        width: Math.min(180, wzorStartowy.width / 2)
        height: width
        sourceSize: Qt.size(width * 2, height * 2)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qfield.name
        font.pointSize: 26
        font.bold: true
        color: "white"
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: wzorStartowy.ziarnoTekst.replace(" - ", " · ")
        font.pointSize: Theme.tipFont.pointSize
        color: "white"
        opacity: 0.75
      }
    }

    // ── po intro: plakietka wersji w prawym dolnym rogu ──
    Row {
      z: 5
      x: wzorStartowy.plakietkaX - width / 2
      y: wzorStartowy.plakietkaY - height / 2
      spacing: 6
      opacity: wzorStartowy.introTrwa ? 0 : 0.85
      visible: opacity > 0
      Behavior on opacity {
        NumberAnimation {
          duration: 600
        }
      }
      Image {
        anchors.verticalCenter: parent.verticalCenter
        source: "qrc:/images/app_logo.svg"
        width: 26
        height: 26
        sourceSize: Qt.size(52, 52)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: wzorStartowy.ziarnoTekst.replace(" - ", " · ")
        font.pointSize: Theme.tipFont.pointSize
        color: "white"
      }
    }
  }

  ScrollView {
    // [WF-WZOR-INTRO] przyciski dopiero po 2 s intra
    opacity: wzorStartowy.introTrwa ? 0 : 1
    Behavior on opacity {
      NumberAnimation {
        duration: 400
      }
    }
    topPadding: Math.max(mainWindow.sceneTopMargin + 58, (mainWindow.height - welcomeLayout.height) / 2 - 50)
    leftPadding: mainWindow.sceneLeftMargin
    rightPadding: mainWindow.sceneRightMargin
    bottomPadding: mainWindow.sceneBottomMargin
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical: QfScrollBar {
      opacity: active
      _maxSize: 4
      _minSize: 2

      Behavior on opacity {
        NumberAnimation {
          duration: 200
        }
      }
    }

    contentItem: welcomeLayout
    contentWidth: welcomeLayout.width
    contentHeight: welcomeLayout.height
    anchors.fill: parent
    clip: true

    ColumnLayout {
      id: welcomeLayout
      spacing: 4

      width: mainWindow.width - mainWindow.sceneLeftMargin - mainWindow.sceneRightMargin

      // [WF-WZOR-STARTOWY] logo NAD nazwą (było obok) — większe logo nie mieści się w rzędzie
      ColumnLayout {
        spacing: 6

        Layout.margins: 6
        Layout.topMargin: 0
        Layout.bottomMargin: 24
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter

        Layout.maximumWidth: parent.width

        QfImageDial {
          id: welcomeScreenLogo
          objectName: "welcomeScreenLogo"

          property real imageSize: Math.min(170, mainWindow.width / 2.2) // [WF-WZOR-STARTOWY] było 96
          property real pressedValue: -1

          Layout.preferredWidth: imageSize
          Layout.preferredHeight: imageSize
          Layout.alignment: Qt.AlignHCenter

          source: "qrc:/images/app_logo.svg"
          rotationOffset: 220
          value: 1

          onPressedChanged: {
            if (pressed) {
              pressedValue = -1;
            } else {
              if (pressedValue == -1 || Math.abs(value - pressedValue) < 0.05) {
                welcomeScreen.showAbout();
              }
              pressedValue = -1;
            }
          }

          onValueChanged: {
            if (pressed && pressedValue == -1) {
              pressedValue = value;
            }
          }
        }

        Text {
          id: welcomeScreenTitle
          objectName: "welcomeScreenTitle"

          Layout.fillWidth: true

          font.pointSize: 24
          font.bold: true
          color: Theme.mainOverlayColor
          text: Qfield.name
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }

        FontMetrics {
          id: welcomeScreenTitleMetrics
          font: welcomeScreenTitle.font
        }
      }

      SwipeView {
        id: feedbackView
        visible: false

        Layout.margins: 6
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        Layout.preferredWidth: Math.min(410, welcomeLayout.width - 30)
        Layout.preferredHeight: Math.max(ohno.childrenRect.height, intro.childrenRect.height, ohyeah.childrenRect.height)
        clip: true

        Behavior on Layout.preferredHeight {
          NumberAnimation {
            duration: 100
            easing.type: Easing.InQuad
          }
        }

        interactive: false
        currentIndex: 1
        Item {
          id: ohno

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: feedbackView.width - 12
              text: qsTr("We're sorry to hear that. Click on the button below to comment or seek support.")
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              Layout.bottomMargin: 10

              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr("Reach out")
                icon.source: QfTheme.getThemeVectorIcon('ic_create_white_24dp')

                onClicked: {
                  Qt.openUrlExternally("https://www.qfield.org/");
                  feedbackView.Layout.preferredHeight = 0;
                }
              }
            }
          }
        }

        Item {
          id: intro

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: feedbackView.width - 12
              text: qsTr("Hey there, how do you like your experience with %1 so far?").arg(Qfield.name)
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              Layout.bottomMargin: 10
              QfToolButton {
                iconSource: QfTheme.getThemeVectorIcon('ic_dissatisfied_white_24dp')
                iconColor: QfTheme.mainOverlayColor
                bgcolor: QfTheme.mainColor
                round: true

                onClicked: {
                  feedbackView.currentIndex = 0;
                }
              }
              QfToolButton {
                iconSource: QfTheme.getThemeVectorIcon('ic_satisfied_white_24dp')
                iconColor: QfTheme.mainOverlayColor
                bgcolor: QfTheme.mainColor
                round: true

                onClicked: {
                  if (Qt.platform.os === "android" || Qt.platform.os === "ios" || Qt.platform.os === "windows") {
                    feedbackView.currentIndex = 2;
                  } else {
                    feedbackView.Layout.preferredHeight = 0;
                  }
                }
              }
            }
          }
        }
        Item {
          id: ohyeah

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: feedbackView.width - 12
              text: qsTr("That's great! We'd love for you to click on the button below and leave a review.")
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              Layout.margins: 6
              Layout.bottomMargin: 10
              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr("Rate us")
                icon.source: QfTheme.getThemeVectorIcon('ic_star_white_24dp')

                onClicked: {
                  if (Qt.platform.os === "windows") {
                    Qt.openUrlExternally("https://apps.microsoft.com/detail/xp99h3bcx4bw7f");
                  } else if (Qt.platform.os === "android") {
                    Qt.openUrlExternally("market://details?id=ch.opengis.qfield");
                  } else if (Qt.platform.os === "ios") {
                    Qt.openUrlExternally("itms-apps://itunes.apple.com/app/qfield-for-qgis/id1531726814");
                  }
                  feedbackView.Layout.preferredHeight = 0;
                }
              }
            }
          }
        }
      }

      SwipeView {
        id: collectionView
        visible: false

        Layout.margins: 0
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        Layout.preferredWidth: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? Math.min(1160, welcomeLayout.width - 40) : Math.min(410, welcomeLayout.width - 20)
        Layout.preferredHeight: Math.max(collectionOhno.childrenRect.height, collectionIntro.childrenRect.height)
        clip: true

        Behavior on Layout.preferredHeight {
          NumberAnimation {
            duration: 100
            easing.type: Easing.InQuad
          }
        }

        interactive: false
        currentIndex: 1
        Item {
          id: collectionOhno

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: collectionView.width - 12
              text: qsTr("Anonymized metrics collection has been disabled. You can re-enable through the settings panel.")
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }

        Item {
          id: collectionIntro

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: collectionView.width - 12
              text: qsTr("To improve stability for everyone, %1 collects and sends anonymized metrics.").arg(Qfield.name)
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
              Layout.bottomMargin: 10
              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr('I agree')

                onClicked: {
                  qfieldSettings.enableInfoCollection = true;
                  collectionView.visible = false;
                }
              }

              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr('I prefer not')
                bgcolor: "transparent"
                color: QfTheme.mainColor

                onClicked: {
                  qfieldSettings.enableInfoCollection = false;
                  collectionView.visible = false;
                }
              }
            }
          }
        }
      }

      Text {
        id: welcomeText
        visible: !feedbackView.visible && text !== ""
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.topMargin: 2
        Layout.bottomMargin: 10
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        text: ""
        font: Theme.defaultFont
        color: Theme.mainOverlayColor
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Rectangle {
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        Layout.fillWidth: true
        Layout.maximumWidth: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? 1160 : 410
        Layout.preferredHeight: welcomeActions.height
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        color: "transparent"

        ColumnLayout {
          id: welcomeActions
          width: parent.width
          spacing: 12

          // WorkFieldGIS 19.10.2026 [WF-NOWY-PROJEKT-JEDYNY] — w miejscu paska
          // „Nowy z szablonu”. Szablony usunięte (decyzja Piotra); zostaje jedno
          // okno „Nowy projekt” z pustymi polami, to samo co w Menu.
          QfButton {
            Layout.alignment: Qt.AlignHCenter
            topPadding: 8
            bottomPadding: 8
            leftPadding: 14
            rightPadding: 14
            text: qsTr("Nowy projekt")
            icon.source: Theme.getThemeVectorIcon("ic_add_white_24dp")
            onClicked: dashBoard.nowyProjekt()
          }

          Text {
            id: recentText
            Layout.fillWidth: true
            Layout.topMargin: 18
            visible: table.count > 0
            text: qsTr("Recently Opened")
            font.pointSize: QfTheme.tipFont.pointSize
            font.bold: true
            color: Theme.mainOverlayColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.bottomMargin: 4
            text: qsTr("Otwórz lokalne projekty i dane…")
            font.pointSize: Theme.tipFont.pointSize
            font.underline: true
            color: Theme.mainOverlayColor
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              onClicked: {
                platformUtilities.requestStoragePermission();
                showLocalDataPicker();
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: table.height
            color: "transparent"

            GridView {
              id: table

              // WorkField: na komputerze siatka kolumn zamiast jednej listy
              readonly property int kolumny: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? Math.max(1, Math.floor(width / 360)) : 1

              ScrollBar.vertical: QfScrollBar {}
              flickableDirection: Flickable.AutoFlickIfNeeded
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              width: parent.width
              height: contentItem.childrenRect.height
              cellWidth: Math.floor(width / kolumny)
              cellHeight: 140

              delegate: QfProjectThumbnail {
                width: table.cellWidth - 8

                property string path: ProjectPath
                property var type: ProjectType
                property int changesCount: {
                  const cloudProjectId = QfCloudUtils.getProjectId(ProjectPath);
                  if (cloudProjectId !== "") {
                    const project = cloudProjectsModel.findProject(cloudProjectId);
                    if (project) {
                      return project.deltasCount;
                    }
                  }
                  return 0;
                }
                property bool isOutdated: {
                  const cloudProjectId = QfCloudUtils.getProjectId(ProjectPath);
                  if (cloudProjectId !== "") {
                    const project = cloudProjectsModel.findProject(cloudProjectId);
                    if (project) {
                      return project.isOutdated;
                    }
                  }
                  return 0;
                }
                readonly property bool showSync: isOutdated
                readonly property bool showPush: changesCount > 0

                objectName: "loadProjectItem_1" // todo, suffix with e.g. ProjectTitle
                previewImageSource: welcomeScreen.visible ? ProjectThumbnail !== "" ? QfUrlUtils.fromString(ProjectThumbnail) : 'image://projects/' + ProjectPath : ''
                showType: true

                primaryBadge.badgeText.text: changesCount > 0 ? changesCount : ''
                primaryBadge.badgeText.color: QfTheme.light
                primaryBadge.visible: showSync || showPush
                primaryBadge.color: showSync ? QfTheme.mainColor : QfTheme.cloudColor
                primaryBadge.border.color: QfTheme.mainBackgroundColor
                primaryBadge.border.width: 1
                primaryBadge.enableGradient: showSync && showPush

                projectTypeSource: switch (ProjectType) {
                case 0:
                  return QfTheme.getThemeVectorIcon('ic_map_param_48dp');     // local project
                case 1:
                  return QfTheme.getThemeVectorIcon('ic_cloud_project_param_48dp'); // cloud project
                case 2:
                  return QfTheme.getThemeVectorIcon('ic_file_param_48dp');    // local dataset
                default:
                  return '';
                }
                projectTitle.text: ProjectTitle
                projectNote: {
                  var notes = [];
                  if (index == 0) {
                    var firstRun = settings && !settings.value("/QField/FirstRunFlag", false);
                    if (!firstRun && firstShown === false)
                      notes.push(qsTr("Last session"));
                  }
                  // WorkFieldGIS 22.10.2026 — projekt na karcie SD
                  if (iface.naKarcie(ProjectPath))
                    notes.unshift(qsTr("SD · karta"));
                  if (ProjectPath === registry.defaultProject) {
                    notes.push(qsTr("Default project"));
                  }
                  if (ProjectPath === registry.baseMapProject) {
                    notes.push(qsTr("Base map"));
                  }
                  if (notes.length > 0) {
                    return notes.join('; ');
                  } else {
                    return "";
                  }
                }
              }

              MouseArea {
                property Item pressedItem
                anchors.fill: parent
                onClicked: mouse => {
                  var item = table.itemAt(mouse.x, mouse.y);
                  if (item) {
                    switch (item.type) {
                    case QfRecentProjectListModel.CloudProject:
                    case QfRecentProjectListModel.LocalProject:
                    case QfRecentProjectListModel.LocalDataset:
                      if (item.type === QfRecentProjectListModel.CloudProject && cloudConnection.hasToken && cloudConnection.status !== QfCloudConnection.LoggedIn) {
                        cloudConnection.login();
                      }
                      iface.loadFile(item.path, item.projectTitle.text);
                      break;
                    case QfRecentProjectListModel.LinkProject:
                      iface.importUrl(item.path, item.projectTitle.text, true);
                      break;
                    }
                  }
                }
                onPressed: mouse => {
                  var item = table.itemAt(mouse.x, mouse.y);
                  if (item) {
                    pressedItem = item;
                    pressedItem.isPressed = true;
                  }
                }
                onCanceled: {
                  if (pressedItem) {
                    pressedItem.isPressed = false;
                    pressedItem = null;
                  }
                }
                onReleased: {
                  if (pressedItem) {
                    pressedItem.isPressed = false;
                    pressedItem = null;
                  }
                }
                onPressAndHold: mouse => {
                  var item = table.itemAt(mouse.x, mouse.y);
                  if (item) {
                    recentProjectActions.recentProjectPath = item.path;
                    recentProjectActions.recentProjectType = item.type;
                    recentProjectActions.popup(mouse.x, mouse.y);
                  }
                }
              }

              QfMenu {
                id: recentProjectActions

                property string recentProjectPath: ''
                property int recentProjectType: 0

                title: qsTr('Recent Project Actions')

                topMargin: mainWindow.sceneTopMargin
                bottomMargin: mainWindow.sceneBottomMargin

                MenuItem {
                  id: defaultProject
                  visible: recentProjectActions.recentProjectType != 2

                  font: QfTheme.defaultFont
                  width: parent.width
                  height: visible ? 48 : 0
                  leftPadding: QfTheme.menuItemCheckLeftPadding
                  checkable: true
                  checked: recentProjectActions.recentProjectPath === registry.defaultProject

                  text: qsTr("Default project")
                  onTriggered: {
                    registry.defaultProject = recentProjectActions.recentProjectPath === registry.defaultProject ? '' : recentProjectActions.recentProjectPath;
                  }
                }

                MenuItem {
                  id: baseMapProject
                  visible: recentProjectActions.recentProjectType != 2

                  font: QfTheme.defaultFont
                  width: parent.width
                  height: visible ? 48 : 0
                  leftPadding: QfTheme.menuItemCheckLeftPadding
                  checkable: true
                  checked: recentProjectActions.recentProjectPath === registry.baseMapProject

                  text: qsTr("Individual datasets base map")
                  onTriggered: {
                    registry.baseMapProject = recentProjectActions.recentProjectPath === registry.baseMapProject ? '' : recentProjectActions.recentProjectPath;
                  }
                }

                MenuSeparator {
                  visible: baseMapProject.visible
                  width: parent.width
                  height: visible ? undefined : 0
                }

                MenuItem {
                  id: removeProject

                  font: QfTheme.defaultFont
                  width: parent.width
                  height: visible ? 48 : 0
                  leftPadding: QfTheme.menuItemIconlessLeftPadding

                  text: qsTr("Remove from recently opened")
                  onTriggered: {
                    model.removeRecentProject(recentProjectActions.recentProjectPath);
                    model.reloadModel();
                  }
                }
              }
            }
          }

          RowLayout {
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.bottomMargin: mainWindow.sceneBottomMargin
            Label {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              topPadding: 10
              bottomPadding: 10
              font: QfTheme.tipFont
              wrapMode: Text.WordWrap
              color: Theme.mainOverlayColor

              text: registry.defaultProject != '' ? qsTr('Load default project on launch') : qsTr('Load last opened project on launch')

              MouseArea {
                anchors.fill: parent
                onClicked: reloadOnLaunch.checked = !reloadOnLaunch.checked
              }
            }

            QfSwitch {
              id: reloadOnLaunch
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignVCenter
              width: implicitContentWidth

              checked: registry.loadProjectOnLaunch
              onCheckedChanged: {
                registry.loadProjectOnLaunch = checked;
              }
            }
          }
        }
      }
    }
  }

  Column {
    spacing: 4
    anchors {
      top: parent.top
      left: parent.left
      topMargin: mainWindow.sceneTopMargin + 4
      leftMargin: mainWindow.sceneLeftMargin + 4
    }

    QfActionButton {
      id: currentProjectButton
      toolImage: QfTheme.getThemeVectorIcon('ic_arrow_left_white_24dp')
      toolText: qsTr('Return to map')
      backgroundless: true
      visible: qgisProject && !!qgisProject.homePath
      innerActionIcon.visible: false

      onClicked: {
        welcomeScreen.visible = false;
      }
    }

    QfToolButton {
      id: settingsButton
      iconSource: QfTheme.getThemeVectorIcon('ic_tune_white_24dp')
      iconColor: QfTheme.mainTextColor
      bgcolor: "transparent"
      round: true

      onClicked: {
        showSettings();
      }
    }
  }

  QfToolButton {
    id: exitButton
    visible: (Qt.platform.os === "ios" || Qt.platform.os === "android" || mainWindow.sceneBorderless)
    anchors {
      top: parent.top
      right: parent.right
      topMargin: mainWindow.sceneTopMargin + 4
      rightMargin: mainWindow.sceneRightMargin + 4
    }
    iconSource: QfTheme.getThemeVectorIcon('ic_shutdown_24dp')
    iconColor: QfTheme.mainTextColor
    bgcolor: "transparent"
    round: true

    onClicked: {
      mainWindow.closeAlreadyRequested = true;
      mainWindow.close();
    }
  }

  // Sparkles & unicorns
  Rectangle {
    anchors.fill: parent
    color: "#00000000"
    visible: welcomeScreenLogo.value < 0.1

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      propagateComposedEvents: true
      onReleased: mouse.accepted = false
      onDoubleClicked: mouse.accepted = false
      onPressAndHold: mouse.accepted = false
      onClicked: mouse => {
        burstSomeSparkles(mouse.x, mouse.y);
        mouse.accepted = false;
      }
      onPressed: mouse => {
        burstSomeSparkles(mouse.x, mouse.y);
        mouse.accepted = false;
      }
      onPositionChanged: mouse => {
        burstSomeSparkles(mouse.x, mouse.y);
        mouse.accepted = false;
      }
    }

    ParticleSystem {
      id: particles
      running: welcomeScreenLogo.value < 0.1
    }

    ParticleSystem {
      id: unicorns
      running: welcomeScreenLogo.value < 0.1
    }

    ImageParticle {
      anchors.fill: parent
      system: particles
      source: "qrc:///particleresources/star.png"
      sizeTable: "qrc:///images/sparkleSize.png"
      alpha: 1
      colorVariation: 0.3
    }

    ImageParticle {
      anchors.fill: parent
      system: unicorns
      source: "qrc:///images/icons/unicorn.png"
      alpha: 1
      redVariation: 0
      blueVariation: 0
      greenVariation: 0
      rotation: 0
      rotationVariation: 360
    }

    Emitter {
      id: emitterParticles
      x: -100
      y: -100
      system: particles
      emitRate: 60
      lifeSpan: 700
      size: 50
      sizeVariation: 10
      maximumEmitted: 100
      velocity: AngleDirection {
        angle: 0
        angleVariation: 360
        magnitude: 100
        magnitudeVariation: 50
      }
    }

    Emitter {
      id: emitterUnicorns
      x: -100
      y: -100
      system: unicorns
      emitRate: 20
      lifeSpan: 900
      size: 70
      sizeVariation: 10
      maximumEmitted: 100
      velocity: AngleDirection {
        angle: 90
        angleVariation: 20
        magnitude: 200
        magnitudeVariation: 50
      }
    }
  }

  function burstSomeSparkles(x, y) {
    emitterParticles.burst(50, x, y);
    emitterUnicorns.burst(1, x, y);
  }

  function adjustWelcomeScreen() {
    if (visible) {
      if (firstShown) {
        welcomeText.text = "";
      } else {
        var firstRun = !settings.valueBool("/QField/FirstRunDone", false);
        if (firstRun) {
          welcomeText.text = table.count > 0 ? qsTr("First time using this application? Try the sample projects listed below.") : "";
          settings.setValue("/QField/FirstRunDone", true);
          settings.setValue("/QField/showMapCanvasGuide", true);
        } else {
          welcomeText.text = "";
        }
      }
    }
  }

  Component.onCompleted: {
    // [WF-NOWY-PROJEKT-JEDYNY] folder `templates` nie jest już zakładany
    adjustWelcomeScreen();
    var runCount = settings.value("/QField/RunCount", 0) * 1;
    var feedbackFormShown = settings.value("/QField/FeedbackFormShown", false);
    if (!feedbackFormShown) {
      var now = new Date();
      var dt = settings.value("/QField/FirstRunDate", "");
      if (dt != "") {
        dt = new Date(dt);
        var daysToPrompt = 30;
        var runsToPrompt = 5;
        if (runCount >= runsToPrompt && (now - dt) >= (daysToPrompt * 24 * 60 * 60 * 1000)) {
          if (Qfield.name === "QField") {
            feedbackView.visible = true;
          }
          settings.setValue("/QField/FeedbackFormShown", true);
        }
      } else {
        settings.setValue("/QField/FirstRunDate", now.toISOString());
      }
    }
    if (platformUtilities.capabilities & QfPlatformUtilities.SentryFramework) {
      var collectionFormShown = settings.value("/QField/CollectionFormShownV2", false);
      if (!collectionFormShown) {
        collectionView.visible = true;
        settings.setValue("/QField/CollectionFormShownV2", true);
      }
    }
    settings.setValue("/QField/RunCount", runCount + 1);
    if (registry.defaultProject != '') {
      if (!QfFileUtils.fileExists(registry.defaultProject)) {
        registry.defaultProject = '';
      }
    }
  }

  onVisibleChanged: {
    if (!visible) {
      welcomeText.text = "";
      feedbackView.visible = false;
      collectionView.visible = false;
      firstShown = true;
    }
  }

  Keys.onReleased: event => {
    if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
      if (qgisProject.fileName != '') {
        event.accepted = true;
        visible = false;
      } else {
        event.accepted = false;
      }
    }
  }

  Dialog {
    id: templateNameDialog

    property string templatePath: ""
    property string templateName: ""

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true
    title: qsTr("Nowy projekt z szablonu")
    standardButtons: Dialog.Ok | Dialog.Cancel
    focus: visible

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: qsTr("Nazwa projektu:")
        font: Theme.defaultFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      TextField {
        id: templateNameField
        Layout.fillWidth: true
        font: Theme.defaultFont
        selectByMouse: true
      }
    }

    onAccepted: {
      if (templateNameField.text.trim() !== "") {
        welcomeScreen.createProjectFromTemplate(templatePath, templateNameField.text.trim());
      }
    }
  }
}
