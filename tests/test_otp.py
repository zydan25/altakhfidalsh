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

def test_existing_customer_is_detected_even_when_stored_in_local_yemen_format(app, client):
    from app.extensions import db
    from app.models import Customer

    with app.app_context():
        customer = Customer(
            phone_normalized="0771234567",
            name="عميل موجود",
            status="active",
            onboarding_completed=True,
        )
        db.session.add(customer)
        db.session.commit()

    response = client.post(
        "/api/v1/customer/auth/check-phone",
        json={"phone": "771234567"},
    )
    assert response.status_code == 200
    item = response.get_json()["item"]
    assert item["phone"] == "967771234567"
    assert item["exists"] is True
    assert item["has_password"] is False
