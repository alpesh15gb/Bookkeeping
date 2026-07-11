# ApexBooks — Contact Module Validation Checklist
> **Gate**: Before replicating the Contacts pattern to Products, Chart of Accounts, Banking Profiles, etc.

---

## 1. Analyzer Gate
- [x] dart analyze lib — **0 errors, 0 warnings**
- [ ] dart analyze test — **0 errors**

## 2. Unit Tests (Model)
- [x] romJson parses full ContactResponse
- [x] romJson handles minimal response
- [x] 	oJson produces correct request body
- [x] ContactType enum roundtrip
- [x] RegistrationType enum roundtrip

## 3. Widget Tests (Reusable Components)
- [ ] EntityDetailPage renders sections, chips, timeline
- [ ] ApexGSTField renders with label
- [ ] ApexDropdownField renders with options
- [ ] ApexMoneyField renders with label and value
- [ ] ApexDataTable renders rows from column config
- [ ] ApexDataTable triggers sort callback

## 4. Functional Validation (Live Backend)
### Create
- [ ] POST /masters/contacts returns 201 with ContactResponse
- [ ] Missing name returns 422
- [ ] Invalid contact_type returns 422
- [ ] Invalid gstin returns 422

### List
- [ ] GET /masters/contacts returns paginated list
- [ ] ?page=1&limit=20 works
- [ ] ?search=Rajesh filters results
- [ ] ?contact_type=CUSTOMER filters by type
- [ ] ?sort_by=name&sort_order=asc sorts

### Get
- [ ] GET /masters/contacts/{id} returns full contact
- [ ] Non-existent id returns 404

### Update
- [ ] PUT /masters/contacts/{id} returns updated contact
- [ ] PUT with invalid data returns 422
- [ ] Updating non-existent id returns 404

### Delete
- [ ] DELETE /masters/contacts/{id} returns 204
- [ ] Deleting contact with invoices returns 409
- [ ] Deleting non-existent id returns 404

## 5. State Validation
- [ ] Pull-to-refresh reloads list
- [ ] Pagination (scroll to bottom loads next page)
- [ ] Search debounced, no duplicate requests
- [ ] Filters persist across navigation
- [ ] Sorting sorts on column header tap
- [ ] Optimistic update on create/update/delete
- [ ] Offline queue replays after reconnect
- [ ] Cache invalidated after create/update/delete
- [ ] List refreshes after returning from detail/form

## 6. Error Handling
- [ ] 401 → redirect to login
- [ ] 403 → show permission denied
- [ ] 404 → show "Not found" with back action
- [ ] 409 → show conflict message
- [ ] 422 → show validation errors on fields
- [ ] 429 → show rate limit with retry
- [ ] 500 → show error with retry button
- [ ] Network offline → show offline banner
- [ ] Network offline → queue mutation
- [ ] Network offline → replay on reconnection

## 7. Desktop Validation
- [ ] Keyboard navigation (Tab, Shift+Tab, Enter, Escape)
- [ ] Command palette (Ctrl+K) searchable
- [ ] Responsive layout >1200px
- [ ] Column resizing in data table
- [ ] Context menu on right-click
- [ ] Large dataset (10k rows) — smooth scroll
- [ ] Large dataset (100k rows) — < 2s initial load

## 8. Mobile Validation
- [ ] Layout adapts to <600px width
- [ ] Landscape orientation works
- [ ] Bottom sheets instead of dialogs
- [ ] Keyboard overlap handled
- [ ] Scrolling smooth
- [ ] Safe areas respected (notch, home indicator)

## 9. Performance
- [ ] Initial load < 1s (10 contacts)
- [ ] Search response < 500ms
- [ ] Pagination no jank (60fps)
- [ ] Filter speed < 1s
- [ ] Memory < 50MB steady state
- [ ] No render overflow warnings
- [ ] No duplicate API calls

## 10. CRUD Reference Checklist
- [x] 0 analyzer errors
- [ ] 0 runtime exceptions
- [ ] 0 overflow/layout issues
- [ ] No duplicate API calls
- [ ] No stale cache
- [ ] No memory leaks
- [ ] No navigation issues
- [ ] No inconsistent spacing
- [ ] No hardcoded values
- [ ] No unused code

## 11. Code Coverage Target
- [ ] Model: 100% (fromJson, toJson, enums)
- [ ] Repository: 100% (path, cachePrefix, parseOne)
- [ ] Controller: 100% (CRUD operations)
- [ ] List Screen: 90% (render, search, paginate)
- [ ] Form Screen: 90% (create, edit, validate)
- [ ] Detail Screen: 90% (render, actions, timeline)

---

## Sign-off

**Contacts module validated by**: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  
**Date**: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  
**Backend commit**: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  
**Frontend commit**: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

✅ **Proceed to Products module**  
❌ **Issues to fix before proceeding**:
