from django.http import JsonResponse


async def health_check(request):
    return JsonResponse({"status": "ok", "service": "backup_device"})
