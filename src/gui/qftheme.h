/***************************************************************************
  qftheme.h - QfTheme

---------------------
begin                : 22.2.2026
copyright            : (C) 2026 by Kaustuv Pokharel
email                : kaustuv@opengis.ch
***************************************************************************
*                                                                         *
*   This program is free software; you can redistribute it and/or modify  *
*   it under the terms of the GNU General Public License as published by  *
*   the Free Software Foundation; either version 2 of the License, or     *
*   (at your option) any later version.                                   *
*                                                                         *
***************************************************************************/

#ifndef QFTHEME_H
#define QFTHEME_H

#include "qfield_gui_export.h"

#include <QColor>
#include <QFont>
#include <QObject>
#include <QVariantMap>

/**
 * \ingroup gui
 *
 * \brief Provides all color, font scale, and layout constants used throughout
 * the QField UI. Registered as a QML singleton in org.qfield.gui.
 *
 * \note Default colors are loaded from :/theme/theme.json
 */
class QFIELD_GUI_EXPORT QfTheme final : public QObject
{
    Q_OBJECT

    Q_PROPERTY( bool darkTheme READ darkTheme WRITE setDarkTheme NOTIFY darkThemeChanged )
    Q_PROPERTY( QString appearance READ appearance WRITE setAppearance NOTIFY appearanceChanged )

    // Palette tables, exposed for QML code that reads them directly
    Q_PROPERTY( QVariantMap darkThemeColors READ darkThemeColors CONSTANT )
    Q_PROPERTY( QVariantMap lightThemeColors READ lightThemeColors CONSTANT )

    Q_PROPERTY( QColor mainColor READ mainColor WRITE setMainColor NOTIFY mainColorChanged )
    Q_PROPERTY( QColor mainOverlayColor READ mainOverlayColor WRITE setMainOverlayColor NOTIFY mainOverlayColorChanged )
    Q_PROPERTY( QColor mainBackgroundColor READ mainBackgroundColor WRITE setMainBackgroundColor NOTIFY mainBackgroundColorChanged )
    Q_PROPERTY( QColor mainBackgroundColorSemiOpaque READ mainBackgroundColorSemiOpaque WRITE setMainBackgroundColorSemiOpaque NOTIFY mainBackgroundColorSemiOpaqueChanged )
    Q_PROPERTY( QColor mainTextColor READ mainTextColor WRITE setMainTextColor NOTIFY mainTextColorChanged )
    Q_PROPERTY( QColor mainTextDisabledColor READ mainTextDisabledColor WRITE setMainTextDisabledColor NOTIFY mainTextDisabledColorChanged )
    Q_PROPERTY( QColor secondaryTextColor READ secondaryTextColor WRITE setSecondaryTextColor NOTIFY secondaryTextColorChanged )
    Q_PROPERTY( QColor controlBackgroundColor READ controlBackgroundColor WRITE setControlBackgroundColor NOTIFY controlBackgroundColorChanged )
    Q_PROPERTY( QColor controlBackgroundAlternateColor READ controlBackgroundAlternateColor WRITE setControlBackgroundAlternateColor NOTIFY controlBackgroundAlternateColorChanged )
    Q_PROPERTY( QColor controlBackgroundDisabledColor READ controlBackgroundDisabledColor WRITE setControlBackgroundDisabledColor NOTIFY controlBackgroundDisabledColorChanged )
    Q_PROPERTY( QColor controlBorderColor READ controlBorderColor WRITE setControlBorderColor NOTIFY controlBorderColorChanged )
    Q_PROPERTY( QColor buttonColor READ buttonColor WRITE setButtonColor NOTIFY buttonColorChanged )
    Q_PROPERTY( QColor buttonBackgroundColor READ buttonBackgroundColor WRITE setButtonBackgroundColor NOTIFY buttonBackgroundColorChanged )
    Q_PROPERTY( QColor toolButtonColor READ toolButtonColor WRITE setToolButtonColor NOTIFY toolButtonColorChanged )
    Q_PROPERTY( QColor toolButtonBackgroundColor READ toolButtonBackgroundColor WRITE setToolButtonBackgroundColor NOTIFY toolButtonBackgroundColorChanged )
    Q_PROPERTY( QColor toolButtonBackgroundSemiOpaqueColor READ toolButtonBackgroundSemiOpaqueColor WRITE setToolButtonBackgroundSemiOpaqueColor NOTIFY toolButtonBackgroundSemiOpaqueColorChanged )
    Q_PROPERTY( QColor scrollBarBackgroundColor READ scrollBarBackgroundColor WRITE setScrollBarBackgroundColor NOTIFY scrollBarBackgroundColorChanged )
    Q_PROPERTY( QColor groupBoxBackgroundColor READ groupBoxBackgroundColor WRITE setGroupBoxBackgroundColor NOTIFY groupBoxBackgroundColorChanged )
    Q_PROPERTY( QColor groupBoxSurfaceColor READ groupBoxSurfaceColor WRITE setGroupBoxSurfaceColor NOTIFY groupBoxSurfaceColorChanged )
    Q_PROPERTY( QColor goodColor READ goodColor WRITE setGoodColor NOTIFY goodColorChanged )
    Q_PROPERTY( QColor warningColor READ warningColor WRITE setWarningColor NOTIFY warningColorChanged )
    Q_PROPERTY( QColor errorColor READ errorColor WRITE setErrorColor NOTIFY errorColorChanged )

    Q_PROPERTY( QColor mainColorSemiOpaque READ mainColorSemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor darkRed READ darkRed NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor darkGray READ darkGray NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor darkGraySemiOpaque READ darkGraySemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor gray READ gray NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor lightGray READ lightGray NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor lightestGray READ lightestGray NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor lightestGraySemiOpaque READ lightestGraySemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor light READ light NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor cloudColor READ cloudColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor positionColor READ positionColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor positionColorSemiOpaque READ positionColorSemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor positionBackgroundColor READ positionBackgroundColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor darkPositionColor READ darkPositionColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor darkPositionColorSemiOpaque READ darkPositionColorSemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor accuracyBad READ accuracyBad NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor accuracyTolerated READ accuracyTolerated NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor accuracyExcellent READ accuracyExcellent NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor navigationColor READ navigationColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor navigationColorSemiOpaque READ navigationColorSemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor navigationBackgroundColor READ navigationBackgroundColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor sensorBackgroundColor READ sensorBackgroundColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor bookmarkDefault READ bookmarkDefault NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor bookmarkOrange READ bookmarkOrange NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor bookmarkRed READ bookmarkRed NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor bookmarkBlue READ bookmarkBlue NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor qfieldcloudBlue READ qfieldcloudBlue NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor vertexColor READ vertexColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor vertexColorSemiOpaque READ vertexColorSemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor vertexSelectedColor READ vertexSelectedColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor vertexSelectedColorSemiOpaque READ vertexSelectedColorSemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor vertexNewColor READ vertexNewColor NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor vertexNewColorSemiOpaque READ vertexNewColorSemiOpaque NOTIFY themeDataLoaded )
    Q_PROPERTY( QColor processingPreview READ processingPreview NOTIFY themeDataLoaded )

    Q_PROPERTY( qreal fontScale READ fontScale WRITE setFontScale NOTIFY fontScaleChanged )

    // WorkField 23.08.2026 — wyglad interfejsu ustawiany przez uzytkownika.
    // Motyw z theme.json zostaje podkladem; te trzy rzeczy sa nadpisaniem,
    // ktore przezywa restart i przezywa przelaczenie jasny/ciemny.
    //! Rodzina czcionki interfejsu; pusty napis = czcionka systemowa
    Q_PROPERTY( QString rodzinaCzcionki READ rodzinaCzcionki WRITE ustawRodzineCzcionki NOTIFY fontScaleChanged )
    //! Rozmiar podstawowy w punktach; 0 = rozmiar systemowy
    Q_PROPERTY( qreal rozmiarCzcionki READ rozmiarCzcionki WRITE ustawRozmiarCzcionki NOTIFY fontScaleChanged )

    Q_PROPERTY( QFont defaultFont READ defaultFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont tinyFont READ tinyFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont tipFont READ tipFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont resultFont READ resultFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont strongFont READ strongFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont strongTipFont READ strongTipFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont strongResultFont READ strongResultFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont secondaryTitleFont READ secondaryTitleFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont titleFont READ titleFont NOTIFY fontScaleChanged )
    Q_PROPERTY( QFont strongTitleFont READ strongTitleFont NOTIFY fontScaleChanged )

    Q_PROPERTY( int toolButtonSize READ toolButtonSize WRITE setToolButtonSize NOTIFY toolButtonSizeChanged )

    // WorkField: gęstość interfejsu akcji — jedno źródło metryk dla całej
    // aplikacji (0 zwarta / 1 standardowa / 2 rękawice) oraz forma paneli
    // akcji (0 lista wierszy / 1 kafle). Zmiana odświeża interfejs od razu.
    Q_PROPERTY( int gestosc READ gestosc WRITE setGestosc NOTIFY gestoscChanged )
    Q_PROPERTY( int ukladAkcji READ ukladAkcji WRITE setUkladAkcji NOTIFY ukladAkcjiChanged )
    Q_PROPERTY( int wysokoscWiersza READ wysokoscWiersza NOTIFY gestoscChanged )
    Q_PROPERTY( int wysokoscKafla READ wysokoscKafla NOTIFY gestoscChanged )
    Q_PROPERTY( int odstepAkcji READ odstepAkcji NOTIFY gestoscChanged )
    Q_PROPERTY( int kolumnyKafli READ kolumnyKafli NOTIFY gestoscChanged )

    Q_PROPERTY( int popupScreenEdgeVerticalMargin READ popupScreenEdgeVerticalMargin CONSTANT )
    Q_PROPERTY( int popupScreenEdgeHorizontalMargin READ popupScreenEdgeHorizontalMargin CONSTANT )
    Q_PROPERTY( int menuItemIconlessLeftPadding READ menuItemIconlessLeftPadding CONSTANT )
    Q_PROPERTY( int menuItemLeftPadding READ menuItemLeftPadding CONSTANT )
    Q_PROPERTY( int menuItemCheckLeftPadding READ menuItemCheckLeftPadding CONSTANT )

  public:
    explicit QfTheme( QObject *parent = nullptr );

    enum BaseAppearance
    {
      UseSettingsAppearance,
      SystemAppearance,
      DarkAppearance,
      LightAppearance
    };
    Q_ENUM( BaseAppearance )

    /**
   * Applies the dark/light/system appearance setting and the matching color palette.
   * An optional \a extraColors map is applied on top for per-call overrides.
   * \note Material.theme and Application.styleHints.colorScheme are QML-only
   * APIs; bind them in QML to \c QfTheme.darkTheme instead
   */
    Q_INVOKABLE void applyAppearance( const QVariantMap &extraColors = QVariantMap(), BaseAppearance baseAppearance = UseSettingsAppearance );

    /**
   * Applies a map of { propertyName -> color } to this object.
   * Only writable properties are touched; invalid colors and unknown keys are skipped.
   */
    Q_INVOKABLE void applyColors( const QVariantMap &colors );

    /**
   * Returns the raster icon resource path for \a name, selecting the density
   * bucket that best matches the current screen PPI.
   */
    Q_INVOKABLE QString getThemeIcon( const QString &name ) const;

    /**
   * Returns the SVG icon resource path for \a name.
   */
    Q_INVOKABLE QString getThemeVectorIcon( const QString &name ) const;

    /**
   * Converts \a color to a CSS \c rgba() string.
   */
    Q_INVOKABLE QString colorToHtml( const QColor &color ) const;

    /**
   * Converts a map of property/value pairs to an inline style string.
   * QColor values are converted via colorToHtml().
   */
    Q_INVOKABLE QString toInlineStyles( const QVariantMap &styleProperties ) const;

    /**
   * Sets the system font point size used for all font properties.
   * Called by qgismobileapp.cpp after the QML engine is up.
   */
    Q_INVOKABLE void setSystemFontPointSize( qreal size );

    /**
   * Sets the screen PPI used for icon density selection.
   * Called by qgismobileapp.cpp after the QML engine is up.
   */
    Q_INVOKABLE void setScreenPpi( qreal ppi );

    QVariantMap darkThemeColors() const { return mDarkThemeColors; }
    QVariantMap lightThemeColors() const { return mLightThemeColors; }

    QColor mainColor() const { return mMainColor; }
    void setMainColor( const QColor &color );

    QColor mainOverlayColor() const { return mMainOverlayColor; }
    void setMainOverlayColor( const QColor &color );

    QColor mainBackgroundColor() const { return mMainBackgroundColor; }
    void setMainBackgroundColor( const QColor &color );

    QColor mainBackgroundColorSemiOpaque() const { return mMainBackgroundColorSemiOpaque; }
    void setMainBackgroundColorSemiOpaque( const QColor &color );

    QColor mainTextColor() const { return mMainTextColor; }
    void setMainTextColor( const QColor &color );

    QColor mainTextDisabledColor() const { return mMainTextDisabledColor; }
    void setMainTextDisabledColor( const QColor &color );

    QColor secondaryTextColor() const { return mSecondaryTextColor; }
    void setSecondaryTextColor( const QColor &color );

    QColor controlBackgroundColor() const { return mControlBackgroundColor; }
    void setControlBackgroundColor( const QColor &color );

    QColor controlBackgroundAlternateColor() const { return mControlBackgroundAlternateColor; }
    void setControlBackgroundAlternateColor( const QColor &color );

    QColor controlBackgroundDisabledColor() const { return mControlBackgroundDisabledColor; }
    void setControlBackgroundDisabledColor( const QColor &color );

    QColor controlBorderColor() const { return mControlBorderColor; }
    void setControlBorderColor( const QColor &color );

    QColor buttonColor() const { return mButtonColor; }
    void setButtonColor( const QColor &color );

    QColor buttonBackgroundColor() const { return mButtonBackgroundColor; }
    void setButtonBackgroundColor( const QColor &color );

    QColor toolButtonColor() const { return mToolButtonColor; }
    void setToolButtonColor( const QColor &color );

    QColor toolButtonBackgroundColor() const { return mToolButtonBackgroundColor; }
    void setToolButtonBackgroundColor( const QColor &color );

    QColor toolButtonBackgroundSemiOpaqueColor() const { return mToolButtonBackgroundSemiOpaqueColor; }
    void setToolButtonBackgroundSemiOpaqueColor( const QColor &color );

    QColor scrollBarBackgroundColor() const { return mScrollBarBackgroundColor; }
    void setScrollBarBackgroundColor( const QColor &color );

    QColor groupBoxBackgroundColor() const { return mGroupBoxBackgroundColor; }
    void setGroupBoxBackgroundColor( const QColor &color );

    QColor groupBoxSurfaceColor() const { return mGroupBoxSurfaceColor; }
    void setGroupBoxSurfaceColor( const QColor &color );

    QColor goodColor() const { return mGoodColor; }
    void setGoodColor( const QColor &color );

    QColor warningColor() const { return mWarningColor; }
    void setWarningColor( const QColor &color );

    QColor errorColor() const { return mErrorColor; }
    void setErrorColor( const QColor &color );

    QColor mainColorSemiOpaque() const { return mMainColorSemiOpaque; }
    QColor darkRed() const { return mDarkRed; }
    QColor darkGray() const { return mDarkGray; }
    QColor darkGraySemiOpaque() const { return mDarkGraySemiOpaque; }
    QColor gray() const { return mGray; }
    QColor lightGray() const { return mLightGray; }
    QColor lightestGray() const { return mLightestGray; }
    QColor lightestGraySemiOpaque() const { return mLightestGraySemiOpaque; }
    QColor light() const { return mLight; }
    QColor cloudColor() const { return mCloudColor; }
    QColor positionColor() const { return mPositionColor; }
    QColor positionColorSemiOpaque() const { return mPositionColorSemiOpaque; }
    QColor positionBackgroundColor() const { return mPositionBackgroundColor; }
    QColor darkPositionColor() const { return mDarkPositionColor; }
    QColor darkPositionColorSemiOpaque() const { return mDarkPositionColorSemiOpaque; }
    QColor accuracyBad() const { return mAccuracyBad; }
    QColor accuracyTolerated() const { return mAccuracyTolerated; }
    QColor accuracyExcellent() const { return mAccuracyExcellent; }
    QColor navigationColor() const { return mNavigationColor; }
    QColor navigationColorSemiOpaque() const { return mNavigationColorSemiOpaque; }
    QColor navigationBackgroundColor() const { return mNavigationBackgroundColor; }
    QColor sensorBackgroundColor() const { return mSensorBackgroundColor; }
    QColor bookmarkDefault() const { return mBookmarkDefault; }
    QColor bookmarkOrange() const { return mBookmarkOrange; }
    QColor bookmarkRed() const { return mBookmarkRed; }
    QColor bookmarkBlue() const { return mBookmarkBlue; }
    QColor qfieldcloudBlue() const { return mQfieldcloudBlue; }
    QColor vertexColor() const { return mVertexColor; }
    QColor vertexColorSemiOpaque() const { return mVertexColorSemiOpaque; }
    QColor vertexSelectedColor() const { return mVertexSelectedColor; }
    QColor vertexSelectedColorSemiOpaque() const { return mVertexSelectedColorSemiOpaque; }
    QColor vertexNewColor() const { return mVertexNewColor; }
    QColor vertexNewColorSemiOpaque() const { return mVertexNewColorSemiOpaque; }
    QColor processingPreview() const { return mProcessingPreview; }

    QString appearance() const { return mAppearance; }
    void setAppearance( const QString &appearance );

    bool darkTheme() const { return mDarkTheme; }
    void setDarkTheme( bool dark );

    qreal fontScale() const { return mFontScale; }
    void setFontScale( qreal scale );

    QString rodzinaCzcionki() const { return mRodzinaCzcionki; }
    void ustawRodzineCzcionki( const QString &rodzina );

    qreal rozmiarCzcionki() const { return mRozmiarCzcionki; }
    void ustawRozmiarCzcionki( qreal punkty );

    //! Lista rodzin czcionek zainstalowanych w systemie, do wyboru w ustawieniach
    Q_INVOKABLE QStringList dostepneCzcionki() const;

    /**
     * Nadpisuje jedna barwe motywu i ZAPAMIETUJE ja. \a nazwaWlasnosci to nazwa
     * wlasnosci QfTheme, np. "mainTextColor" albo "mainBackgroundColor".
     * Nadpisania sa nakladane po kazdym wczytaniu motywu, wiec nie gina przy
     * przelaczeniu jasny/ciemny.
     */
    Q_INVOKABLE void ustawBarweWlasna( const QString &nazwaWlasnosci, const QColor &barwa );

    //! Czy dana barwa jest dzis nadpisana przez uzytkownika
    Q_INVOKABLE bool barwaNadpisana( const QString &nazwaWlasnosci ) const;

    //! Kasuje wszystkie nadpisania barw i wraca do motywu z pliku
    Q_INVOKABLE void przywrocBarwyMotywu();

    QFont defaultFont() const { return makeFont( 1.0, false ); }
    QFont tinyFont() const { return makeFont( 0.75, false ); }
    QFont tipFont() const { return makeFont( 0.875, false ); }
    QFont resultFont() const { return makeFont( 0.9, false ); }
    QFont strongFont() const { return makeFont( 1.0, true ); }
    QFont strongTipFont() const { return makeFont( 0.875, true ); }
    QFont strongResultFont() const { return makeFont( 0.9, true ); }
    QFont secondaryTitleFont() const { return makeFont( 1.125, false ); }
    QFont titleFont() const { return makeFont( 1.25, false ); }
    QFont strongTitleFont() const { return makeFont( 1.25, true ); }

    int toolButtonSize() const { return mToolButtonSize; }
    void setToolButtonSize( int size );

    int gestosc() const { return mGestosc; }
    void setGestosc( int gestosc );
    int ukladAkcji() const { return mUkladAkcji; }
    void setUkladAkcji( int uklad );

    int wysokoscWiersza() const { return mGestosc == 0 ? 48 : ( mGestosc == 2 ? 64 : 56 ); }
    int wysokoscKafla() const { return mGestosc == 0 ? 64 : ( mGestosc == 2 ? 84 : 72 ); }
    int odstepAkcji() const { return mGestosc == 0 ? 4 : ( mGestosc == 2 ? 8 : 6 ); }
    int kolumnyKafli() const { return 3; }

    int popupScreenEdgeVerticalMargin() const { return 40; }
    int popupScreenEdgeHorizontalMargin() const { return 20; }
    int menuItemIconlessLeftPadding() const { return 52; }
    int menuItemLeftPadding() const { return 12; }
    int menuItemCheckLeftPadding() const { return 16; }

  signals:
    void mainColorChanged();
    void mainOverlayColorChanged();
    void mainBackgroundColorChanged();
    void mainBackgroundColorSemiOpaqueChanged();
    void mainTextColorChanged();
    void mainTextDisabledColorChanged();
    void secondaryTextColorChanged();
    void controlBackgroundColorChanged();
    void controlBackgroundAlternateColorChanged();
    void controlBackgroundDisabledColorChanged();
    void controlBorderColorChanged();
    void buttonColorChanged();
    void buttonBackgroundColorChanged();
    void toolButtonColorChanged();
    void toolButtonBackgroundColorChanged();
    void toolButtonBackgroundSemiOpaqueColorChanged();
    void scrollBarBackgroundColorChanged();
    void groupBoxBackgroundColorChanged();
    void groupBoxSurfaceColorChanged();
    void goodColorChanged();
    void warningColorChanged();
    void errorColorChanged();
    void appearanceChanged();
    void darkThemeChanged();
    void fontScaleChanged();
    void toolButtonSizeChanged();
    void gestoscChanged();
    void ukladAkcjiChanged();
    void themeDataLoaded();
    void screenPpiChanged();

  private:
    QFont makeFont( qreal scaleFactor, bool bold ) const;
    void loadFromJson();

    QVariantMap mDarkThemeColors;
    QVariantMap mLightThemeColors;

    QColor mMainColor;
    QColor mMainOverlayColor;
    QColor mMainBackgroundColor;
    QColor mMainBackgroundColorSemiOpaque;
    QColor mMainTextColor;
    QColor mMainTextDisabledColor;
    QColor mSecondaryTextColor;
    QColor mControlBackgroundColor;
    QColor mControlBackgroundAlternateColor;
    QColor mControlBackgroundDisabledColor;
    QColor mControlBorderColor;
    QColor mButtonColor;
    QColor mButtonBackgroundColor;
    QColor mToolButtonColor;
    QColor mToolButtonBackgroundColor;
    QColor mToolButtonBackgroundSemiOpaqueColor;
    QColor mScrollBarBackgroundColor;
    QColor mGroupBoxBackgroundColor;
    QColor mGroupBoxSurfaceColor;

    QColor mMainColorSemiOpaque;
    QColor mDarkRed;
    QColor mDarkGray;
    QColor mDarkGraySemiOpaque;
    QColor mGray;
    QColor mLightGray;
    QColor mLightestGray;
    QColor mLightestGraySemiOpaque;
    QColor mLight;
    QColor mGoodColor;
    QColor mWarningColor;
    QColor mErrorColor;
    QColor mCloudColor;
    QColor mPositionColor;
    QColor mPositionColorSemiOpaque;
    QColor mPositionBackgroundColor;
    QColor mDarkPositionColor;
    QColor mDarkPositionColorSemiOpaque;
    QColor mAccuracyBad;
    QColor mAccuracyTolerated;
    QColor mAccuracyExcellent;
    QColor mNavigationColor;
    QColor mNavigationColorSemiOpaque;
    QColor mNavigationBackgroundColor;
    QColor mSensorBackgroundColor;
    QColor mBookmarkDefault;
    QColor mBookmarkOrange;
    QColor mBookmarkRed;
    QColor mBookmarkBlue;
    QColor mQfieldcloudBlue;
    QColor mVertexColor;
    QColor mVertexColorSemiOpaque;
    QColor mVertexSelectedColor;
    QColor mVertexSelectedColorSemiOpaque;
    QColor mVertexNewColor;
    QColor mVertexNewColorSemiOpaque;
    QColor mProcessingPreview;

    QString mAppearance;
    bool mDarkTheme = false;
    qreal mFontScale = 1.0;
    int mToolButtonSize = 48;
    int mGestosc = 1;
    int mUkladAkcji = 0;
    qreal mSystemFontPointSize = 14.0;
    QString mRodzinaCzcionki;
    qreal mRozmiarCzcionki = 0.0;
    QVariantMap mBarwyWlasne;
    qreal mScreenPpi = 160.0;
};

#endif // QFTHEME_H
