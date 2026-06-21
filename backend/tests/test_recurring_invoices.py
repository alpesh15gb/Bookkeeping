def _recurring_payload(contact, product, **overrides):
    payload = {
        "contact_id": str(contact.id),
        "template_name": "Monthly AMC",
        "frequency": "MONTHLY",
        "interval_count": 1,
        "next_date": "2026-07-01",
        "end_mode": "NEVER",
        "pos_state_code": "27",
        "items": [
            {
                "product_id": str(product.id),
                "description": "AMC",
                "quantity": "1",
                "rate": "1000.00",
                "discount": "0.00",
                "hsn_sac": "9983",
                "gst_rate": "18.00",
            }
        ],
    }
    payload.update(overrides)
    return payload


def test_create_recurring_invoice_saves_end_date(
    client,
    combined_headers,
    contact_factory,
    product_factory,
):
    contact = contact_factory()
    product = product_factory(hsn_sac="9983")

    response = client.post(
        "/api/v1/recurring-invoices",
        json=_recurring_payload(
            contact,
            product,
            end_mode="ON_DATE",
            end_date="2027-03-31",
        ),
        headers=combined_headers(),
    )

    assert response.status_code == 201
    data = response.json()
    assert data["end_mode"] == "ON_DATE"
    assert data["end_date"] == "2027-03-31"
    assert data["max_occurrences"] is None


def test_create_recurring_invoice_requires_end_date_for_on_date(
    client,
    combined_headers,
    contact_factory,
    product_factory,
):
    contact = contact_factory()
    product = product_factory(hsn_sac="9983")

    response = client.post(
        "/api/v1/recurring-invoices",
        json=_recurring_payload(contact, product, end_mode="ON_DATE"),
        headers=combined_headers(),
    )

    assert response.status_code == 422


def test_create_recurring_invoice_saves_max_occurrences(
    client,
    combined_headers,
    contact_factory,
    product_factory,
):
    contact = contact_factory()
    product = product_factory(hsn_sac="9983")

    response = client.post(
        "/api/v1/recurring-invoices",
        json=_recurring_payload(
            contact,
            product,
            end_mode="AFTER_N",
            max_occurrences=6,
        ),
        headers=combined_headers(),
    )

    assert response.status_code == 201
    data = response.json()
    assert data["end_mode"] == "AFTER_N"
    assert data["end_date"] is None
    assert data["max_occurrences"] == 6


def test_create_recurring_invoice_requires_max_occurrences_for_after_n(
    client,
    combined_headers,
    contact_factory,
    product_factory,
):
    contact = contact_factory()
    product = product_factory(hsn_sac="9983")

    response = client.post(
        "/api/v1/recurring-invoices",
        json=_recurring_payload(contact, product, end_mode="AFTER_N"),
        headers=combined_headers(),
    )

    assert response.status_code == 422


def test_recurring_invoice_stops_after_max_occurrences(
    client,
    combined_headers,
    contact_factory,
    product_factory,
    db_session,
    tenant,
):
    from src.infrastructure.database.models import NumberingSeries, TenantSetting

    contact = contact_factory()
    product = product_factory(hsn_sac="9983")
    db_session.add(
        TenantSetting(
            tenant_id=tenant.id,
            key="origin_state_code",
            value="27",
        )
    )
    db_session.add(
        NumberingSeries(
            tenant_id=tenant.id,
            document_type="INVOICE",
            prefix="INV-",
            next_number=1,
            padding_digits=4,
            is_active=True,
        )
    )
    db_session.commit()

    create_response = client.post(
        "/api/v1/recurring-invoices",
        json=_recurring_payload(
            contact,
            product,
            end_mode="AFTER_N",
            max_occurrences=1,
        ),
        headers=combined_headers(),
    )
    assert create_response.status_code == 201
    recurring_id = create_response.json()["id"]

    generate_response = client.post(
        f"/api/v1/recurring-invoices/{recurring_id}/generate",
        headers=combined_headers(),
    )

    assert generate_response.status_code == 200
    detail_response = client.get(
        f"/api/v1/recurring-invoices/{recurring_id}",
        headers=combined_headers(),
    )
    assert detail_response.status_code == 200
    detail = detail_response.json()
    assert detail["occurrences_created"] == 1
    assert detail["is_active"] is False
