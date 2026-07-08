import { defineStore } from 'pinia'
import Cookies from 'js-cookie'
import { adminLogin, adminLogout, getCurrentAdminUser, type AdminUserInfo } from '@xzs/api-client'

const adminUserNameKey = 'adminUserName'

export const useUserStore = defineStore('adminUser', {
  state: () => ({
    userName: Cookies.get(adminUserNameKey) ?? '',
    userInfo: null as AdminUserInfo | null,
    hasCheckedSession: false
  }),
  getters: {
    isAuthenticated: (state) => Boolean(state.userName && state.userInfo)
  },
  actions: {
    async login(payload: { userName: string; password: string; remember: boolean }) {
      const result = await adminLogin(payload)
      if (result.code === 1) {
        this.userName = payload.userName
        Cookies.set(adminUserNameKey, payload.userName, { expires: payload.remember ? 30 : undefined })
        await this.initUserInfo()
      }
      return result
    },
    async initUserInfo() {
      const result = await getCurrentAdminUser()
      this.hasCheckedSession = true
      this.userInfo = result.response ?? null
      if (this.userInfo?.userName) {
        this.userName = this.userInfo.userName
        Cookies.set(adminUserNameKey, this.userInfo.userName, { expires: 30 })
      }
      return result
    },
    async logout() {
      await adminLogout().catch(() => undefined)
      this.clear()
    },
    clear() {
      this.userName = ''
      this.userInfo = null
      this.hasCheckedSession = true
      Cookies.remove(adminUserNameKey)
    }
  }
})
