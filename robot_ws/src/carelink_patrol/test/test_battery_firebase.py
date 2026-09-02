from carelink_patrol.battery_firebase import estimate_battery_percent


def test_estimate_battery_percent_limits():
    assert estimate_battery_percent(9.0) == 0
    assert estimate_battery_percent(12.6) == 100
    assert estimate_battery_percent(13.0) == 100


def test_estimate_battery_percent_curve_points():
    assert estimate_battery_percent(11.1) == 40
    assert estimate_battery_percent(11.4) == 60
    assert estimate_battery_percent(12.0) == 85


def test_estimate_battery_percent_interpolates():
    assert estimate_battery_percent(11.25) == 50

