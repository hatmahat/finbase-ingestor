from supabase import Client


def get_or_create(client: Client, file_name: str, file_type: str) -> int:
    """Upsert into imports by file_name and return the row id."""
    result = (
        client.table("imports")
        .upsert({"file_name": file_name, "file_type": file_type}, on_conflict="file_name", ignore_duplicates=False)
        .execute()
    )
    return result.data[0]["id"]
