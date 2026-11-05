plugins { kotlin("jvm") }
repositories { mavenCentral() }
kotlin { jvmToolchain(17) }
dependencies { testImplementation(kotlin("test")) }
tasks.test { useJUnitPlatform() }
