defmodule ExGrok.CollectionsTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Collections, Fixtures}

  @stub_name :collections_test_stub

  describe "management endpoints use the management host" do
    test "create POSTs collection_name to management-api host" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "management-api.x.ai"
        assert conn.method == "POST"
        assert conn.request_path == "/v1/collections"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["collection_name"] == "SEC Filings"
        Req.Test.json(conn, Fixtures.sample_collection())
      end)

      mgmt = Fixtures.test_management_client(@stub_name)
      assert {:ok, coll} = Collections.create(mgmt, "SEC Filings")
      assert Collections.extract_collection_id(coll) == "coll-xyz"
    end

    test "add_document POSTs to /collections/:id/documents/:file_id" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "management-api.x.ai"
        assert conn.method == "POST"
        assert conn.request_path == "/v1/collections/coll-xyz/documents/file-abc123"
        Req.Test.json(conn, %{"ok" => true})
      end)

      mgmt = Fixtures.test_management_client(@stub_name)
      assert {:ok, %{"ok" => true}} = Collections.add_document(mgmt, "coll-xyz", "file-abc123")
    end

    test "delete removes a collection" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/v1/collections/coll-xyz"
        Req.Test.json(conn, %{"deleted" => true})
      end)

      mgmt = Fixtures.test_management_client(@stub_name)
      assert {:ok, %{"deleted" => true}} = Collections.delete(mgmt, "coll-xyz")
    end
  end

  describe "search uses the normal inference host" do
    test "POSTs query + collection_ids to /documents/search on api.x.ai" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "api.x.ai"
        assert conn.request_path == "/v1/documents/search"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["query"] == "revenue"
        assert params["source"] == %{"collection_ids" => ["coll-xyz"]}
        assert params["retrieval_mode"] == %{"type" => "hybrid"}
        Req.Test.json(conn, Fixtures.sample_search_results())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, resp} = Collections.search(client, "revenue", collection_ids: ["coll-xyz"])
      assert [%{"file_id" => "file-abc123"}] = Collections.extract_search_results(resp)
    end
  end
end
