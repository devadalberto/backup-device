from django.shortcuts import render

from .models import MediaFile


def gallery(request):
    """Display thumbnails and metadata for all ``MediaFile`` instances."""

    media_files = MediaFile.objects.all()
    return render(request, "media_lake/gallery.html", {"media_files": media_files})
