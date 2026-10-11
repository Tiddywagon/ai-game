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
