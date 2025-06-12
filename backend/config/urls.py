from config.views.health import health_check
from django.contrib import admin
from django.urls import path
from media_lake.views import gallery

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health/", health_check, name="health_check"),
    path("gallery/", gallery, name="gallery"),
]
