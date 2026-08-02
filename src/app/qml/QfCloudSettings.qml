import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * Konto chmury WorkField (NextCloud).
 *
 * Jedno konto obsługuje wszystko, co idzie przez serwer: szablony zespołowe,
 * wydania zadań i zwroty z terenu. Bez niego aplikacja widzi tylko szablony
 * publiczne — i to jest w porządku, bo do pracy w terenie one wystarczą.
 *
 * Hasło aplikacji, nie hasło do konta: generuje się je w NextCloud
 * (Ustawienia → Bezpieczeństwo) i można unieważnić osobno, nie ruszając konta.
 * Przy zgubionym telefonie to różnica między jedną unieważnioną kartą
 * a zmianą wszystkich zamków.
 */
ColumnLayout {
  id: cloudSettings

  property var settingsPage

  spacing: 8

  //! adres serwera bez ukośnika na końcu
  property string serwer: settings.value("workfield/cloud-url", "https://ekolaby.net/cloud")
  property string login: settings.value("workfield/cloud-user", "")
  property string haslo: settings.value("workfield/cloud-pass", "")
  property string stan: ""

  function zapisz() {
    settings.setValue("workfield/cloud-url", poleSerwer.text.replace(/\/$/, ""));
    settings.setValue("workfield/cloud-user", poleLogin.text.trim());
    settings.setValue("workfield/cloud-pass", poleHaslo.text);
    serwer = poleSerwer.text.replace(/\/$/, "");
    login = poleLogin.text.trim();
    haslo = poleHaslo.text;
  }

  //! Sprawdza połączenie zapytaniem PROPFIND o katalog domowy użytkownika.
  function sprawdz() {
    zapisz();
    if (login === "" || haslo === "") {
      stan = qsTr("uzupełnij login i hasło aplikacji");
      return;
    }
    stan = qsTr("sprawdzam…");
    const xhr = new XMLHttpRequest();
    xhr.open("PROPFIND", serwer + "/remote.php/dav/files/" + login + "/", true);
    xhr.setRequestHeader("Depth", "0");
    xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(login + ":" + haslo));
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) {
        return;
      }
      if (xhr.status === 207 || xhr.status === 200) {
        stan = qsTr("połączono jako %1").arg(login);
      } else if (xhr.status === 401) {
        stan = qsTr("odrzucono — sprawdź login i hasło aplikacji");
      } else {
        stan = qsTr("nie udało się połączyć (kod %1)").arg(xhr.status);
      }
    };
    xhr.send();
  }

  Label {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    text: qsTr("Konto chmury WorkField")
    font: Theme.strongTipFont
    color: Theme.mainTextColor
  }

  Label {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    text: qsTr("Bez konta widoczne są tylko szablony publiczne. Konto daje dostęp do szablonów zespołu, wydań zadań i odkładania zwrotów.")
    font: Theme.tipFont
    color: Theme.secondaryTextColor
  }

  Label {
    text: qsTr("Adres serwera")
    font: Theme.tinyFont
    color: Theme.secondaryTextColor
  }
  TextField {
    id: poleSerwer
    Layout.fillWidth: true
    text: cloudSettings.serwer
    placeholderText: "https://ekolaby.net/cloud"
    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
  }

  Label {
    text: qsTr("Login")
    font: Theme.tinyFont
    color: Theme.secondaryTextColor
  }
  TextField {
    id: poleLogin
    Layout.fillWidth: true
    text: cloudSettings.login
    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
  }

  Label {
    text: qsTr("Hasło aplikacji")
    font: Theme.tinyFont
    color: Theme.secondaryTextColor
  }
  TextField {
    id: poleHaslo
    Layout.fillWidth: true
    text: cloudSettings.haslo
    echoMode: TextInput.Password
    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
  }

  Label {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    text: qsTr("Hasło aplikacji utworzysz w NextCloud: Ustawienia → Bezpieczeństwo → Utwórz nowe hasło aplikacji. Nie używaj hasła do konta — hasło aplikacji można unieważnić osobno.")
    font: Theme.tinyFont
    color: Theme.secondaryTextColor
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.topMargin: 6
    spacing: 8

    Button {
      text: qsTr("Sprawdź połączenie")
      onClicked: cloudSettings.sprawdz()
    }

    Button {
      flat: true
      text: qsTr("Wyczyść")
      onClicked: {
        poleLogin.text = "";
        poleHaslo.text = "";
        cloudSettings.zapisz();
        cloudSettings.stan = qsTr("konto usunięte — zostają szablony publiczne");
      }
    }
  }

  Label {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    visible: cloudSettings.stan !== ""
    text: cloudSettings.stan
    font: Theme.tipFont
    color: cloudSettings.stan.indexOf(qsTr("połączono")) === 0 ? Theme.mainTextColor : Theme.secondaryTextColor
  }
}
