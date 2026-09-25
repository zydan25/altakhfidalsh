def test_phone_otp_flow(client):
    request = client.post("/api/v1/customer/auth/request-otp", json={"phone": "771234567"})
    assert request.status_code == 201
    data = request.get_json()['item']
    assert data['phone'] == '967771234567'
    assert 'debug_code' in data
    verified = client.post('/api/v1/customer/auth/verify-otp', json={
        'otp_request_id': data['otp_request_id'], 'code': data['debug_code'], 'device_id': 'test-device'
    })
    assert verified.status_code == 200
    result = verified.get_json()['item']
    assert result['customer_id'] > 0
    assert result['access_token']
    assert result['refresh_token']