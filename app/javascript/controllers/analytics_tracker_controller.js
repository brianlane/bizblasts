import { Controller } from "@hotwired/stimulus"

/**
 * Analytics Tracker Controller
 * 
 * Tracks page views and click events for business analytics.
 * Privacy-first approach: no cookies, anonymous fingerprinting, respects DNT.
 * 
 * Usage:
 *   <body data-controller="analytics-tracker" 
 *         data-analytics-tracker-business-id-value="123"
 *         data-analytics-tracker-track-clicks-value="true">
 */
export default class extends Controller {
  static values = {
    businessId: Number,
    trackClicks: { type: Boolean, default: true },
    trackScrollDepth: { type: Boolean, default: true },
    batchInterval: { type: Number, default: 30000 }, // 30 seconds
    endpoint: { type: String, default: "/api/v1/analytics/track" }
  }

  // Event queue for batching
  eventQueue = []
  sessionId = null
  visitorFingerprint = null
  pageLoadTime = null
  maxScrollDepth = 0
  isPageVisible = true

  // Bound event handlers (stored for cleanup)
  boundHandlers = {}

  connect() {
    // Respect Do Not Track
    if (this.shouldNotTrack()) {
      console.debug("[Analytics] DNT enabled, tracking disabled")
      return
    }

    this.initializeSession()
    this.trackPageView()
    this.setupEventListeners()
    this.startBatchProcessor()
  }

  disconnect() {
    this.sendBeacon() // Send remaining events on disconnect
    this.cleanup()
  }

  // ==================== Initialization ====================

  initializeSession() {
    this.pageLoadTime = Date.now()
    this.sessionId = this.getOrCreateSessionId()
    this.visitorFingerprint = this.generateFingerprint()
  }

  getOrCreateSessionId() {
    // Use sessionStorage for session-scoped ID (clears on browser close)
    let sessionId = sessionStorage.getItem("bz_session_id")
    if (!sessionId) {
      sessionId = this.generateUUID()
      sessionStorage.setItem("bz_session_id", sessionId)
    }
    return sessionId
  }

  generateFingerprint() {
    // Privacy-respecting fingerprint (not unique enough for tracking across sites)
    const components = [
      navigator.userAgent,
      navigator.language,
      screen.width + "x" + screen.height,
      new Date().getTimezoneOffset(),
      navigator.hardwareConcurrency || "unknown"
    ]
    return this.hashCode(components.join("|"))
  }

  generateUUID() {
    // Use cryptographically secure random values to generate a UUID v4
    const bytes = new Uint8Array(16)
    // Prefer window.crypto if available; fall back to globalThis.crypto
    const cryptoObj = (typeof window !== "undefined" && window.crypto) || (typeof globalThis !== "undefined" && globalThis.crypto)
    if (!cryptoObj || !cryptoObj.getRandomValues) {
      throw new Error("Secure random number generator is not available")
    }
    cryptoObj.getRandomValues(bytes)

    // Set version (4) and variant (RFC4122) bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80

    const hex = []
    for (let i = 0; i < bytes.length; i++) {
      hex.push(bytes[i].toString(16).padStart(2, "0"))
    }

    return (
      hex[0] + hex[1] + hex[2] + hex[3] + "-" +
      hex[4] + hex[5] + "-" +
      hex[6] + hex[7] + "-" +
      hex[8] + hex[9] + "-" +
      hex[10] + hex[11] + hex[12] + hex[13] + hex[14] + hex[15]
    )
  }

  hashCode(str) {
    let hash = 0
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    return Math.abs(hash).toString(16).padStart(16, "0")
  }

  shouldNotTrack() {
    return navigator.doNotTrack === "1" || 
           window.doNotTrack === "1" || 
           navigator.msDoNotTrack === "1"
  }

  // ==================== Event Listeners ====================

  setupEventListeners() {
    // Store bound handlers for cleanup
    this.boundHandlers = {
      click: this.handleClick.bind(this),
      scroll: this.handleScroll.bind(this),
      visibilityChange: this.handleVisibilityChange.bind(this),
      beforeUnload: this.handleBeforeUnload.bind(this),
      turboLoad: this.handleTurboLoad.bind(this)
    }

    // Click tracking
    if (this.trackClicksValue) {
      document.addEventListener("click", this.boundHandlers.click, true)
    }

    // Scroll depth tracking
    if (this.trackScrollDepthValue) {
      window.addEventListener("scroll", this.boundHandlers.scroll, { passive: true })
    }

    // Page visibility for time on page
    document.addEventListener("visibilitychange", this.boundHandlers.visibilityChange)

    // Before unload for final event send
    window.addEventListener("beforeunload", this.boundHandlers.beforeUnload)

    // Handle Turbo navigation
    document.addEventListener("turbo:before-visit", this.boundHandlers.beforeUnload)
    document.addEventListener("turbo:load", this.boundHandlers.turboLoad)
  }

  cleanup() {
    if (this.batchTimer) {
      clearInterval(this.batchTimer)
    }

    // Remove all event listeners to prevent memory leaks
    if (this.boundHandlers) {
      if (this.boundHandlers.click) {
        document.removeEventListener("click", this.boundHandlers.click, true)
      }
      if (this.boundHandlers.scroll) {
        window.removeEventListener("scroll", this.boundHandlers.scroll)
      }
      if (this.boundHandlers.visibilityChange) {
        document.removeEventListener("visibilitychange", this.boundHandlers.visibilityChange)
      }
      if (this.boundHandlers.beforeUnload) {
        window.removeEventListener("beforeunload", this.boundHandlers.beforeUnload)
        document.removeEventListener("turbo:before-visit", this.boundHandlers.beforeUnload)
      }
      if (this.boundHandlers.turboLoad) {
        document.removeEventListener("turbo:load", this.boundHandlers.turboLoad)
      }

      this.boundHandlers = {}
    }
  }

  // ==================== Page View Tracking ====================

  trackPageView() {
    const event = {
      type: "page_view",
      timestamp: new Date().toISOString(),
      data: {
        page_path: window.location.pathname,
        page_title: document.title,
        page_type: this.detectPageType(),
        referrer_url: document.referrer || null,
        referrer_domain: this.extractDomain(document.referrer),
        ...this.getUTMParams(),
        ...this.getDeviceInfo(),
        ...this.getViewportInfo()
      }
    }

    this.queueEvent(event)
  }

  detectPageType() {
    const path = window.location.pathname.toLowerCase()
    
    if (path === "/" || path === "") return "home"
    if (path.includes("/services")) return "services"
    if (path.includes("/products")) return "products"
    if (path.includes("/contact")) return "contact"
    if (path.includes("/about")) return "about"
    if (path.includes("/booking") || path.includes("/calendar")) return "booking"
    if (path.includes("/cart") || path.includes("/checkout")) return "checkout"
    if (path.includes("/blog")) return "blog"
    
    return "custom"
  }

  extractDomain(url) {
    if (!url) return null
    try {
      return new URL(url).hostname
    } catch {
      return null
    }
  }

  getUTMParams() {
    const params = new URLSearchParams(window.location.search)
    return {
      utm_source: params.get("utm_source"),
      utm_medium: params.get("utm_medium"),
      utm_campaign: params.get("utm_campaign"),
      utm_term: params.get("utm_term"),
      utm_content: params.get("utm_content")
    }
  }

  getDeviceInfo() {
    const ua = navigator.userAgent
    
    return {
      device_type: this.detectDeviceType(),
      browser: this.detectBrowser(ua),
      browser_version: this.detectBrowserVersion(ua),
      os: this.detectOS(ua),
      screen_resolution: `${screen.width}x${screen.height}`
    }
  }

  detectDeviceType() {
    const ua = navigator.userAgent.toLowerCase()
    if (/mobile|android|iphone|ipod|blackberry|windows phone/i.test(ua)) {
      return "mobile"
    }
    if (/tablet|ipad/i.test(ua)) {
      return "tablet"
    }
    return "desktop"
  }

  detectBrowser(ua) {
    if (ua.includes("Firefox")) return "Firefox"
    if (ua.includes("SamsungBrowser")) return "Samsung"
    if (ua.includes("Opera") || ua.includes("OPR")) return "Opera"
    if (ua.includes("Edg")) return "Edge"
    if (ua.includes("Chrome")) return "Chrome"
    if (ua.includes("Safari")) return "Safari"
    return "Other"
  }

  detectBrowserVersion(ua) {
    // Safari's version is in "Version/X.X" format, not after "Safari/"
    // Safari UA: "...Version/17.4 Safari/605.1.15" - Safari/605 is WebKit build, not Safari version
    if (ua.includes("Safari") && !ua.includes("Chrome") && !ua.includes("Chromium")) {
      const versionMatch = ua.match(/Version\/(\d+)/)
      if (versionMatch) return versionMatch[1]
    }
    const match = ua.match(/(Firefox|Chrome|Opera|Edge|Edg)\/(\d+)/)
    return match ? match[2] : "unknown"
  }

  detectOS(ua) {
    if (ua.includes("Windows")) return "Windows"
    if (ua.includes("Mac OS")) return "macOS"
    if (ua.includes("Linux")) return "Linux"
    if (ua.includes("Android")) return "Android"
    if (ua.includes("iOS") || ua.includes("iPhone") || ua.includes("iPad")) return "iOS"
    return "Other"
  }

  getViewportInfo() {
    return {
      viewport_width: window.innerWidth,
      viewport_height: window.innerHeight
    }
  }

  // ==================== Click Tracking ====================

  handleClick(event) {
    const target = event.target.closest("[data-analytics-track], a, button, [role='button']")
    if (!target) return

    const clickEvent = {
      type: "click",
      timestamp: new Date().toISOString(),
      data: {
        page_path: window.location.pathname,
        page_title: document.title,
        element_type: this.getElementType(target),
        element_identifier: this.getElementIdentifier(target),
        element_text: this.getElementText(target),
        // Use getAttribute('class') to handle SVG elements where className is SVGAnimatedString
        element_class: target.getAttribute('class')?.substring(0, 200),
        // Use getAttribute('href') to handle SVG elements where href is SVGAnimatedString
        element_href: target.getAttribute('href') || null,
        category: this.getClickCategory(target),
        action: this.getClickAction(target),
        label: target.dataset.analyticsLabel || null,
        target_type: target.dataset.analyticsTargetType || null,
        target_id: target.dataset.analyticsTargetId || null,
        conversion_value: target.dataset.analyticsValue ? parseFloat(target.dataset.analyticsValue) : null,
        click_x: event.clientX,
        click_y: event.clientY,
        ...this.getViewportInfo()
      }
    }

    this.queueEvent(clickEvent)
  }

  getElementType(element) {
    if (element.dataset.analyticsTrack) return element.dataset.analyticsTrack
    if (element.tagName === "BUTTON" || element.getAttribute("role") === "button") return "button"
    if (element.tagName === "A") return "link"
    if (element.tagName === "INPUT" && element.type === "submit") return "form_submit"
    if (element.classList.contains("cta") || element.dataset.cta) return "cta"
    // Default to "other" to match the Ruby ClickEvent enum values
    // (button, link, cta, form_submit, image, card, other, conversion)
    return "other"
  }

  getElementIdentifier(element) {
    // Use getAttribute('class') to handle SVG elements where className is SVGAnimatedString
    const firstClass = element.getAttribute('class')?.split(" ")[0]
    return element.id ||
           element.dataset.analyticsId ||
           element.name ||
           firstClass ||
           element.tagName.toLowerCase()
  }

  getElementText(element) {
    const text = element.textContent || element.value || element.alt || element.title || ""
    return text.trim().substring(0, 100)
  }

  getClickCategory(element) {
    // Check for explicit category
    if (element.dataset.analyticsCategory) return element.dataset.analyticsCategory

    // Auto-detect based on context
    // Use getAttribute() to handle SVG elements where href/className are SVGAnimatedString objects
    const href = element.getAttribute('href')?.toLowerCase() || ""
    const classes = element.getAttribute('class')?.toLowerCase() || ""
    const text = element.textContent?.toLowerCase() || ""

    if (href.includes("tel:") || text.includes("call")) return "phone"
    if (href.includes("mailto:")) return "email"
    if (href.includes("/booking") || href.includes("/calendar") || text.includes("book")) return "booking"
    if (href.includes("/products") || href.includes("/cart")) return "product"
    if (href.includes("/services")) return "service"
    if (href.includes("/contact") || text.includes("contact")) return "contact"
    if (href.includes("/estimate")) return "estimate"
    if (classes.includes("social") || this.isSocialLink(href)) return "social"
    if (element.tagName === "A" && !href.startsWith(window.location.origin)) return "external"
    
    return "navigation"
  }

  getClickAction(element) {
    if (element.dataset.analyticsAction) return element.dataset.analyticsAction
    
    const text = element.textContent?.toLowerCase() || ""
    if (text.includes("book")) return "book"
    if (text.includes("add to cart")) return "add_to_cart"
    if (text.includes("contact") || text.includes("submit")) return "submit"
    if (text.includes("call")) return "call"
    if (text.includes("share")) return "share"
    
    return "click"
  }

  isSocialLink(href) {
    const socialDomains = ["facebook.com", "twitter.com", "instagram.com", "linkedin.com", "tiktok.com", "youtube.com"]
    return socialDomains.some(domain => href.includes(domain))
  }

  // ==================== Scroll Tracking ====================

  handleScroll() {
    if (!this.scrollThrottle) {
      this.scrollThrottle = setTimeout(() => {
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop
        const docHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight
        const scrollPercent = Math.round((scrollTop / docHeight) * 100) || 0
        
        if (scrollPercent > this.maxScrollDepth) {
          this.maxScrollDepth = scrollPercent
        }
        
        this.scrollThrottle = null
      }, 100)
    }
  }

  // ==================== Visibility & Unload ====================

  handleVisibilityChange() {
    this.isPageVisible = !document.hidden
    
    if (!this.isPageVisible) {
      // Page became hidden - update time on page
      this.sendBatch()
    }
  }

  handleBeforeUnload() {
    // Send final page view update with time on page and scroll depth
    this.updatePageViewMetrics()
    this.sendBeacon()
  }

  handleTurboLoad() {
    // New page loaded via Turbo - track new page view
    this.pageLoadTime = Date.now()
    this.maxScrollDepth = 0
    this.trackPageView()
  }

  updatePageViewMetrics() {
    const timeOnPage = Math.round((Date.now() - this.pageLoadTime) / 1000)
    
    const updateEvent = {
      type: "page_view_update",
      timestamp: new Date().toISOString(),
      data: {
        page_path: window.location.pathname,
        time_on_page: timeOnPage,
        scroll_depth: this.maxScrollDepth,
        is_exit_page: true
      }
    }

    this.queueEvent(updateEvent)
  }

  // ==================== Event Queue & Sending ====================

  queueEvent(event) {
    event.session_id = this.sessionId
    event.visitor_fingerprint = this.visitorFingerprint
    event.business_id = this.businessIdValue
    
    this.eventQueue.push(event)
    
    // Send immediately if queue is large
    if (this.eventQueue.length >= 10) {
      this.sendBatch()
    }
  }

  startBatchProcessor() {
    this.batchTimer = setInterval(() => {
      this.sendBatch()
    }, this.batchIntervalValue)
  }

  async sendBatch() {
    if (this.eventQueue.length === 0) return

    const events = [...this.eventQueue]
    this.eventQueue = []

    try {
      const response = await fetch(this.endpointValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({ events })
      })

      if (!response.ok) {
        // Re-queue events on failure
        this.eventQueue = [...events, ...this.eventQueue]
        console.error("[Analytics] Failed to send events:", response.status)
      }
    } catch (error) {
      // Re-queue events on network error
      this.eventQueue = [...events, ...this.eventQueue]
      console.error("[Analytics] Network error:", error)
    }
  }

  sendBeacon() {
    if (this.eventQueue.length === 0) return

    const events = [...this.eventQueue]
    this.eventQueue = []

    // Use sendBeacon for reliable delivery on page unload
    const data = JSON.stringify({ events })
    
    try {
      navigator.sendBeacon(this.endpointValue, new Blob([data], { type: "application/json" }))
    } catch (error) {
      console.error("[Analytics] Beacon send failed:", error)
    }
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }

  // ==================== Conversion Tracking ====================

  // Public method to track conversions from other parts of the app
  trackConversion(type, value = null, metadata = {}) {
    // Respect Do Not Track - external callers must not bypass privacy settings
    if (this.shouldNotTrack()) {
      console.debug("[Analytics] DNT enabled, conversion tracking skipped")
      return
    }

    const event = {
      type: "conversion",
      timestamp: new Date().toISOString(),
      session_id: this.sessionId,
      visitor_fingerprint: this.visitorFingerprint,
      data: {
        page_path: window.location.pathname,
        conversion_type: type,
        conversion_value: value,
        ...metadata
      }
    }

    this.queueEvent(event)
    this.sendBatch() // Send conversions immediately
  }
}

