"""
Setup script for the gateway package
"""

from setuptools import setup, find_packages

setup(
    name="mmg-gateway",
    version="1.0.0",
    description="Market Making Game - Python Gateway",
    author="MMG Team",
    packages=find_packages(),
    python_requires=">=3.11",
    install_requires=[
        "fastapi>=0.104.1",
        "uvicorn[standard]>=0.24.0",
        "websockets>=12.0",
        "pydantic>=2.5.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-asyncio>=0.21.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.1.0",
        ]
    },
    entry_points={
        "console_scripts": [
            "mmg-gateway=app.main:main",
        ]
    },
)

