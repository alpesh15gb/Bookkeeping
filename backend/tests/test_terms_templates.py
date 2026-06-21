def test_terms_template_crud(client, combined_headers):
    create_response = client.post(
        "/api/v1/terms-templates",
        json={
            "name": "Standard Invoice Terms",
            "content": "Payment due within 15 days.",
        },
        headers=combined_headers(),
    )
    assert create_response.status_code == 201
    template = create_response.json()
    assert template["name"] == "Standard Invoice Terms"
    assert template["content"] == "Payment due within 15 days."
    assert template["is_preset"] is False

    list_response = client.get(
        "/api/v1/terms-templates",
        headers=combined_headers(),
    )
    assert list_response.status_code == 200
    assert any(item["id"] == template["id"] for item in list_response.json())

    update_response = client.put(
        f"/api/v1/terms-templates/{template['id']}",
        json={
            "name": "Updated Invoice Terms",
            "content": "Payment due within 30 days.",
        },
        headers=combined_headers(),
    )
    assert update_response.status_code == 200
    assert update_response.json()["content"] == "Payment due within 30 days."

    delete_response = client.delete(
        f"/api/v1/terms-templates/{template['id']}",
        headers=combined_headers(),
    )
    assert delete_response.status_code == 204


def test_terms_template_presets_are_available_without_auth(client):
    response = client.get("/api/v1/terms-templates/presets")

    assert response.status_code == 200
    presets = response.json()
    assert presets
    assert {"name", "content"}.issubset(presets[0].keys())
