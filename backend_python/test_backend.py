#!/usr/bin/env python3
"""
Simple test script for RapidResQ backend
Run this to verify the backend is working correctly
"""
import requests
import json
import time

BASE_URL = "http://localhost:8000"

def test_health():
    """Test health endpoint"""
    try:
        response = requests.get(f"{BASE_URL}/health")
        print(f"Health check: {response.status_code}")
        if response.status_code == 200:
            print(f"Response: {response.json()}")
            return True
        else:
            print(f"Error: {response.text}")
            return False
    except Exception as e:
        print(f"Health check failed: {e}")
        return False

def test_active_alerts():
    """Test active alerts endpoint"""
    try:
        response = requests.get(f"{BASE_URL}/alerts/active")
        print(f"Active alerts: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"Alerts: {data}")
            return True
        else:
            print(f"Error: {response.text}")
            return False
    except Exception as e:
        print(f"Active alerts test failed: {e}")
        return False

def test_send_alert():
    """Test sending an alert"""
    try:
        payload = {
            "reporter": "test_user",
            "message": "Test emergency alert",
            "lat": 12.9716,
            "lon": 77.5946
        }
        response = requests.post(f"{BASE_URL}/send_alert",
                               json=payload,
                               headers={"Content-Type": "application/json"})
        print(f"Send alert: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {data}")
            return data.get("alert_id")
        else:
            print(f"Error: {response.text}")
            return None
    except Exception as e:
        print(f"Send alert test failed: {e}")
        return None

def test_cancel_alert(alert_id):
    """Test canceling an alert"""
    if not alert_id:
        print("No alert ID to cancel")
        return False

    try:
        payload = {"alert_id": alert_id}
        response = requests.post(f"{BASE_URL}/cancel_alert",
                               json=payload,
                               headers={"Content-Type": "application/json"})
        print(f"Cancel alert: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {data}")
            return True
        else:
            print(f"Error: {response.text}")
            return False
    except Exception as e:
        print(f"Cancel alert test failed: {e}")
        return False

def main():
    print("🧪 Testing RapidResQ Backend")
    print("=" * 40)

    # Test health
    if not test_health():
        print("❌ Backend not responding")
        return

    print()

    # Test active alerts
    if not test_active_alerts():
        print("❌ Active alerts endpoint failed")
        return

    print()

    # Test sending alert
    alert_id = test_send_alert()
    if alert_id:
        print(f"✅ Alert created with ID: {alert_id}")

        # Wait a moment
        time.sleep(1)

        # Test canceling alert
        if test_cancel_alert(alert_id):
            print("✅ Alert cancelled successfully")
        else:
            print("❌ Alert cancellation failed")
    else:
        print("❌ Alert creation failed")

    print()
    print("🎉 Backend test completed!")

if __name__ == "__main__":
    main()