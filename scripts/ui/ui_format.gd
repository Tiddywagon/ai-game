class_name UiFormat
extends RefCounted
## Text formatting shared by the menus.


## 1234567 -> "1,234,567".
static func thousands(value: int) -> String:
	var digits := str(absi(value))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.substr(digits.length() - 3))
		digits = digits.substr(0, digits.length() - 3)
	groups.push_front(digits)
	return ("-" if value < 0 else "") + ",".join(groups)


## Money with its currency sign: roubles ("₽ 500,000") or dollars ("$ 250").
static func money(amount: int, currency := "RUB") -> String:
	return "%s %s" % [currency_sign(currency), thousands(amount)]


## "₽" or "$". Falls back to "RUB" if the UI font has no rouble sign.
static func currency_sign(currency: String) -> String:
	if currency == "USD":
		return "$"
	return "₽" if ThemeDB.fallback_font.has_char(0x20BD) else "RUB"


## A length of time in words: "3 h", "2 h 30 min", "45 min", "30 s" (seconds rounded up to a minute
## from a minute on).
static func duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%d s" % ceili(maxf(seconds, 0.0))
	var minutes := ceili(seconds / 60.0)
	if minutes < 60:
		return "%d min" % minutes
	return "%d h" % (minutes / 60) if minutes % 60 == 0 else "%d h %02d min" % [minutes / 60, minutes % 60]


## A countdown: "1:02:03" from an hour on, else "12:30".
static func countdown(seconds: float) -> String:
	var left := ceili(maxf(seconds, 0.0))
	if left >= 3600:
		return "%d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]
	return "%d:%02d" % [left / 60, left % 60]
