#pragma once
#include <type_traits>
#include <cassert>
#include <utility>
#include <memory>
#include <mutex>

namespace universaldevkit::helpers::patterns {
	// Instances may differ across DLLs/SOs; process-wide uniqueness is not guaranteed.
	// Without a default constructor, GetInstance requires a prior CreateInstance call.
	template <typename TClass, typename TInstance = void*>
	class Singleton {
	protected:
		using SingletonInherited_t = Singleton<TClass, TInstance>;

	public:
		// Call from dependent singleton constructors so this instance is destroyed after them.
		static void InitSingleton() {
			GetInstance();
		}

		// Creates the instance using its default constructor.
		static TClass& GetInstance() {
			static TClass instance;
			return instance;
		}

	protected:
		friend TClass;
		Singleton() = default;
		Singleton(const Singleton&) = delete;
		Singleton& operator=(const Singleton&) = delete;
		virtual ~Singleton() = default;

	private:
		TInstance instance{}; // Unused by default (TInstance = void*).
	};


	//
	// SingletonUnique
	//
	template <typename TClass>
	class SingletonUnique : public Singleton<SingletonUnique<TClass>, std::unique_ptr<TClass>> {
	private:
		using MyBase_t = Singleton<SingletonUnique<TClass>, std::unique_ptr<TClass>>;

	public:
		using Instance_t = TClass&;

		SingletonUnique() = default;
		~SingletonUnique() = default;

		template <typename ...TArgs>
		static Instance_t CreateInstance(TArgs&&... args) {
			auto& _this = MyBase_t::GetInstance();
			std::unique_lock lk{ _this.mx };

			if (_this.instance == nullptr) {
				_this.instance = std::make_unique<TClass>(std::forward<TArgs>(args)...);
			}

			return *_this.instance;
		}

		static Instance_t GetInstance() {
			auto& _this = MyBase_t::GetInstance();

			if constexpr (std::is_default_constructible_v<TClass>) {
				return CreateInstance();
			}
			else {
				std::unique_lock lk{ _this.mx };
				assert(_this.instance);
				return *_this.instance;
			}
		}

	private:
		std::mutex mx;
	};


	//
	// SingletonShared
	//
	template <typename TClass>
	class SingletonShared : public Singleton<SingletonShared<TClass>, std::shared_ptr<TClass>> {
	private:
		using MyBase_t = Singleton<SingletonShared<TClass>, std::shared_ptr<TClass>>;

	public:
		using Instance_t = std::shared_ptr<TClass>;

		SingletonShared() = default;
		~SingletonShared() = default;

		template <typename ...TArgs>
		static Instance_t CreateInstance(TArgs&&... args) {
			auto& _this = MyBase_t::GetInstance();
			std::unique_lock lk{ _this.mx };

			if (_this.instance == nullptr) {
				_this.instance = std::make_shared<TClass>(std::forward<TArgs>(args)...);
			}

			return _this.instance;
		}


		static Instance_t GetInstance() {
			auto& _this = MyBase_t::GetInstance();

			if constexpr (std::is_default_constructible_v<TClass>) {
				return CreateInstance();
			}
			else {
				std::unique_lock lk{ _this.mx };
				assert(_this.instance);
				return _this.instance;
			}
		}

	private:
		std::mutex mx;
	};


	//
	// SingletonUnscoped
	// DeleteInstance requires external synchronization with all users of the pointer.
	//
	template <typename TClass>
	class SingletonUnscoped : public Singleton<SingletonUnscoped<TClass>, TClass*> {
	private:
		using MyBase_t = Singleton<SingletonUnscoped<TClass>, TClass*>;

	public:
		using Instance_t = TClass*;

		SingletonUnscoped() = default;
		~SingletonUnscoped() = default;

		template <typename ...TArgs>
		static Instance_t CreateInstance(TArgs&&... args) {
			auto& _this = MyBase_t::GetInstance();
			std::unique_lock lk{ _this.mx };

			if (_this.instance == nullptr) {
				_this.instance = new TClass(std::forward<TArgs>(args)...);
			}

			return _this.instance;
		}

		static Instance_t GetInstance() {
			auto& _this = MyBase_t::GetInstance();

			if constexpr (std::is_default_constructible_v<TClass>) {
				return CreateInstance();
			}
			else {
				std::unique_lock lk{ _this.mx };
				assert(_this.instance);
				return _this.instance;
			}
		}

		static void DeleteInstance() {
			auto& _this = MyBase_t::GetInstance();
			std::unique_lock lk{ _this.mx };

			delete _this.instance;
			_this.instance = nullptr;
		}

	private:
		std::mutex mx;
	};
}