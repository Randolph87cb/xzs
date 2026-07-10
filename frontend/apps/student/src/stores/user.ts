import { defineStore } from 'pinia'
import Cookies from 'js-cookie'
import {
  getCurrentStudentUser,
  studentLogin,
  studentLogout,
  type StudentUserInfo
} from '@xzs/api-client'

interface UserState {
  userName: string
  userInfo: StudentUserInfo | null
  imagePath: string
  hasCheckedSession: boolean
}

export const useUserStore = defineStore('user', {
  state: (): UserState => ({
    userName: Cookies.get('studentUserName') ?? '',
    userInfo: readUserInfoCookie(),
    imagePath: Cookies.get('studentImagePath') ?? '',
    hasCheckedSession: false
  }),
  getters: {
    isAuthenticated: (state) => state.userName.length > 0,
    displayName: (state) => state.userInfo?.nickName || state.userInfo?.realName || state.userName
  },
  actions: {
    async login(payload: { userName: string; password: string; remember: boolean }) {
      const result = await studentLogin(payload)

      if (result.code !== 1 || !result.response) {
        throw new Error(result.message)
      }

      this.setUserName(result.response.userName || payload.userName)
      this.setImagePath(result.response.imagePath ?? '')
      await this.initUserInfo()
    },
    async initUserInfo() {
      try {
        const result = await getCurrentStudentUser()

        if (result.response) {
          this.setUserInfo(result.response)
          this.setUserName(result.response.userName)
          this.setImagePath(result.response.imagePath ?? '')
        }
      } finally {
        this.hasCheckedSession = true
      }
    },
    async logout() {
      try {
        await studentLogout()
      } finally {
        this.clear()
      }
    },
    setUserName(userName: string) {
      this.userName = userName
      Cookies.set('studentUserName', userName, { expires: 30 })
    },
    setUserInfo(userInfo: StudentUserInfo) {
      this.userInfo = userInfo
      Cookies.set('studentUserInfo', JSON.stringify(userInfo), { expires: 30 })
    },
    setImagePath(imagePath: string) {
      this.imagePath = imagePath
      if (imagePath) {
        Cookies.set('studentImagePath', imagePath, { expires: 30 })
      } else {
        Cookies.remove('studentImagePath')
      }
    },
    clear() {
      this.userName = ''
      this.userInfo = null
      this.imagePath = ''
      this.hasCheckedSession = true
      Cookies.remove('studentUserName')
      Cookies.remove('studentUserInfo')
      Cookies.remove('studentImagePath')
    }
  }
})

function readUserInfoCookie(): StudentUserInfo | null {
  const rawValue = Cookies.get('studentUserInfo')

  if (!rawValue) {
    return null
  }

  try {
    return JSON.parse(rawValue) as StudentUserInfo
  } catch {
    return null
  }
}
